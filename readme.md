## Yubilock
This Waybar module adds a service that reacts when your YubiKey is removed. By default it locks your screen; it can also take the machine all the way down so the disk returns to its encrypted-at-rest state. The service is controlled by a toggle button in Waybar. This allows you to disable the service to conserve resources when the threat model is low risk, and to enable it when the threat model is higher risk (such as in public places like the airport or coffee shop).

![Screenshot](/resources/Screenshot.png)

The indicator will show the current status of the service and whether a YubiKey is currently inserted. Hovering it tells you what removal will actually do.

This Waybar module is intended to be used with hardware like the following (ref links to support my open source projects):
- [YubiKey](https://amzn.to/4c8m0lY)
- [Magnetic USB A to C Adapter](https://amzn.to/3FLI3mq)
- [USB C Extension Cable](https://amzn.to/4letB6M)

## Dependency
- [usbutils](http://www.linux-usb.org/) needed to run `lsusb`
- `libnotify` (`notify-send`) if you enable notifications

## Part 1: What happens when the key is removed

Removal triggers up to two steps, separated by a cancellable grace period:

```
key removed
    │
    ├─► primaryAction          (immediately)
    │
    ├─► gracePeriod            reinsert the key, or switch yubilock off, to cancel
    │
    └─► secondaryAction        (only if the grace period elapses)
```

| Option | Values | Meaning |
|---|---|---|
| `primaryAction` | `null`, `"lock"`, `"poweroff"`, `"hibernate"` | Runs the instant the key is removed |
| `gracePeriod` | seconds (default `60`) | Cancellation window before the second step |
| `secondaryAction` | `null`, `"lock"`, `"poweroff"`, `"hibernate"` | Runs if the key does not come back |

Defaults are `primaryAction = "lock"` and `secondaryAction = null`, which is the original behaviour — nothing changes until you opt in.

### Taking the disk out of its decrypted state

This is what `secondaryAction = "poweroff"` is for. Some background on why it works that way:

**A root LUKS volume cannot be closed while you are running on it.** `cryptsetup close` fails with `EBUSY` as long as the filesystem is mounted and processes are running on it, so there is no "re-lock the disk and keep working" option for a root-encrypted machine. What actually returns the disk to encrypted-at-rest is powering the machine down, which tears down the dm-crypt mapping and drops the master key from RAM.

**Logout is deliberately not offered.** It is the intuitive answer and it does nothing here: the LUKS mapping stays open, the root filesystem stays decrypted, and the key stays in RAM. You would lose your session and gain less protection than a plain screen lock.

**Hibernate is a poor fit for a snatch-and-run threat model.** It does reach the same encrypted-at-rest state, and it preserves your session, but it has to write all of RAM to swap first — many seconds on a large-memory machine, during which the disk is still decrypted. It also needs a working resume setup (see below). Prefer `poweroff` if the scenario you care about is someone taking the laptop out of your hands.

### Example configurations

```nix
# Original behaviour: lock the screen, nothing else.
{ primaryAction = "lock"; secondaryAction = null; }

# Lock immediately, power off a minute later unless the key comes back.
{ primaryAction = "lock"; gracePeriod = 60; secondaryAction = "poweroff"; }

# Power off the instant the key leaves, no warning, no way to cancel.
{ primaryAction = "poweroff"; secondaryAction = null; }

# "Canary": session stays usable, an unremarkable notification tells you
# yubilock has started, then the machine powers off.
{
  primaryAction = null;
  gracePeriod = 60;
  secondaryAction = "poweroff";
  notify = {
    enable = true;
    title = "Coalmine Canary";
    message = "The canary will no longer sing";
  };
}
```

> **The canary config leaves your session unlocked** for the whole grace period — including the Waybar toggle, which anyone holding the machine can click to switch yubilock off. It buys discretion, not security. Use `primaryAction = "lock"` if the concern is someone physically taking the laptop.

A `secondaryAction` behind a `primaryAction` that ends the session can never run, so `primaryAction = "hibernate"` with `secondaryAction = "poweroff"` is rejected at build time with the rewrite spelled out.

### Notifications

Off by default. With the usual `primaryAction = "lock"` the screen is already locked before a notification would appear, and most lockers hide them anyway. They earn their place in configurations where the session stays usable during the grace period. `notify.title` and `notify.message` are free text, so the message can be something only you recognise rather than an announcement of what your laptop is about to do.

A single notification fires on removal — not a live countdown, which would be noisy and would undercut the point of a discreet message.

### Suspend during the grace period

If the machine suspends mid-countdown (lid close, idle suspend) and is resumed later, the countdown is **abandoned** rather than resumed. Resuming means someone got past the LUKS passphrase, so the countdown's premise no longer holds — and a stale timer firing a power-off forty seconds into the next day's session is not behaviour anyone wants. Yubilock re-arms and times a fresh countdown on the next removal.

## Part 2: Installation

### Option 1: NixOS with Home Manager (Recommended for NixOS users)

1. Import the module in your Home Manager configuration:
   ```nix
   { config, pkgs, ... }:
   {
     imports = [
       /path/to/yubilock/yubilock.nix
     ];

     services.yubilock = {
       enable = true;
       autoRestore = true;       # Restore yubilock state on login

       primaryAction = "lock";
       gracePeriod = 60;
       secondaryAction = "poweroff";
     };
   }
   ```

2. Add the custom module to your Waybar config (see [Waybar Configuration](#part-4-waybar-configuration)).

3. Add the CSS to your Waybar style.css (see [Waybar CSS Style](#part-5-waybar-css-style)).

4. Rebuild your configuration:
   ```bash
   home-manager switch
   ```

There is no step to copy scripts anywhere. The module packages them with their dependencies wrapped in and puts them on your `PATH` as `yubilock`, `yubikey-status` and `yubilock-toggle`, so they cannot go stale or fail because `lsusb` was missing from Waybar's environment.

The module writes `~/.config/yubilock/config`, which both the monitor and the Waybar indicator read, and configures these services:
- `yubilock.service` — monitors YubiKey presence and acts on removal
- `yubilock-restore.service` — restores yubilock state on login (if `autoRestore = true`)

Three read-only options expose the packaged commands so your Waybar config never hardcodes a path:

| Option | Command |
|---|---|
| `services.yubilock.statusCommand` | the Waybar status script |
| `services.yubilock.toggleCommand` | the Waybar click handler |
| `services.yubilock.monitorCommand` | the monitor itself |

### Option 2: Manual Installation (All Linux distributions)
1. Save the scripts to `~/.config/waybar/scripts/`
2. Make them executable:
   ```bash
   chmod +x ~/.config/waybar/scripts/*.sh
   ```
3. Create `~/.config/yubilock/config` if you want anything other than the default lock-only behaviour:
   ```bash
   mkdir -p ~/.config/yubilock
   cat > ~/.config/yubilock/config <<'EOF'
   YUBILOCK_PRIMARY_ACTION="lock"        # "" | lock | poweroff | hibernate
   YUBILOCK_GRACE_PERIOD=60
   YUBILOCK_SECONDARY_ACTION="poweroff"  # "" | lock | poweroff | hibernate
   YUBILOCK_NOTIFY="false"
   YUBILOCK_NOTIFY_TITLE="Yubilock"
   YUBILOCK_NOTIFY_MESSAGE="YubiKey removed."
   EOF
   ```
   With no config file present, yubilock locks the screen on removal and does nothing else.
4. Add the custom module to your Waybar config (see [Waybar Configuration](#part-4-waybar-configuration)).
5. Add the CSS to your Waybar style.css (see [Waybar CSS Style](#part-5-waybar-css-style)).
6. Restart Waybar: `killall waybar && waybar &`

The toggle detects which install it is running under. If a `yubilock.service` user unit exists it starts and stops the monitor through systemd; otherwise it runs the monitor as a background process, as it always did. One script, both install paths.

## Part 3: Making the power-off unstoppable (optional, NixOS)

By default yubilock powers off with `systemctl poweroff -i`. That overrides inhibitor locks — a browser with an open download cannot veto your shutdown — but it is still an orderly shutdown, so a unit that hangs on stop can delay it by up to `DefaultTimeoutStopSec`.

The immediate version, `systemctl poweroff -ff`, skips the system manager and calls `reboot()` directly. That needs `CAP_SYS_BOOT`, which the yubilock **user** service does not have. To make it reachable, import the system module:

```nix
{
  imports = [ /path/to/yubilock/yubilock-system.nix ];

  services.yubilock-poweroff = {
    enable = true;
    allowedGroup = "wheel";
  };
}
```

This adds a root-owned `yubilock-poweroff.service` and a polkit rule letting the chosen group start it without authentication. Yubilock tries `-ff` directly, then the helper unit, then falls back to `systemctl poweroff -i` — so it degrades gracefully if the helper is not installed.

> Be deliberate about `allowedGroup`. Every member gains a passwordless, instant, unclean shutdown of the machine. That is the point, but it is a broader capability than `sudo poweroff` on a system where sudo requires a password. The shutdown is preceded by a time-boxed `sync`, so it is not quite a power-cord yank, but unsaved work is still lost.

## Part 4: Waybar Configuration
Add this to your Waybar configuration file:

4.1 For NixOS:
```nix
"custom/yubilock" = {
  return-type = "json";
  interval = 5;
  signal = 5;
  exec = config.services.yubilock.statusCommand;
  on-click = config.services.yubilock.toggleCommand;
  tooltip = true;
  format = "{icon}";
  format-icons = {
    active = "";
    inactive = "";
  };
};
```
4.2 For other Linux distributions:
```json
"custom/yubilock": {
    "return-type": "json",
    "interval": 5,
    "signal": 5,
    "exec": "$HOME/.config/waybar/scripts/yubikey-status.sh",
    "on-click": "$HOME/.config/waybar/scripts/yubilock-toggle.sh",
    "tooltip": true,
    "format": "{icon}",
    "format-icons": {
      "active": "",
      "inactive": "",
    },
}
```

`signal = 5` matters more than it looks. Without it Waybar only repaints the indicator on its `interval`, so clicking the toggle leaves the icon showing the old state for up to five seconds. Yubilock sends `SIGRTMIN+5` whenever the state changes, and this line is what makes Waybar listen — with it, the icon flips the instant you click.

## Part 5: Waybar CSS Style
Add this to your Waybar style.css file:

```css
#custom-yubilock {
    padding: 0 10px;
    border-radius: 10px;
    margin: 6px 0;
}

#custom-yubilock.yubilock-on {
    background-color: #26a65b;
    color: #ffffff;
}

/* Enabled *and* configured with a secondaryAction — removal will take the
   machine down, not just lock it. */
#custom-yubilock.yubilock-armed {
    background-color: #f39c12;
    color: #ffffff;
}

#custom-yubilock.yubilock-off {
    background-color: #e74c3c;
    color: #ffffff;
}

#custom-yubilock.yubilock-on:hover,
#custom-yubilock.yubilock-armed:hover,
#custom-yubilock.yubilock-off:hover {
    background-color: #2980b9;
}
```

The bar text itself stays generic in every mode; only the colour and the tooltip reveal that a `secondaryAction` is configured. If you would rather not signal even that much, give `.yubilock-armed` the same colour as `.yubilock-on`.

## Troubleshooting

Yubilock logs to `~/.cache/yubilock.log`, including the configuration it loaded at startup, every arm/disarm, and why a countdown was cancelled. To rehearse the behaviour without risking a shutdown, set `secondaryAction = null` and watch the log — detection, locking, cancel-on-reinsert and toggle-off all run identically.

If you configure `hibernate` on a machine that cannot resume from it (no resume device, no swap), yubilock warns at startup with a critical notification and powers off instead of hibernating. It will not silently do nothing — that would leave the disk decrypted while you believed it was protected.

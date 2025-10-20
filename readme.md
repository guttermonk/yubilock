## Yubilock
This Waybar module adds a service that will lock your screen when your Yubikey is removed. The service is controlled by a toggle button in Waybar. This allows you to disable the service to conserve resources when the threat model is low risk, and to enable it when the threat model is higher risk (such as in public places like the airport or coffee shop).

![Screenshot](/resources/Screenshot.png)

The indicator will show the current status of the service and whether a YubiKey is currently inserted.

This Waybar module is intended to be used with hardware like the following (ref links to support my open source projects):
- [YubiKey](https://amzn.to/4c8m0lY)
- [Magnetic USB A to C Adapter](https://amzn.to/3FLI3mq)
- [USB C Extension Cable](https://amzn.to/4letB6M)

## Dependency
- [usbutils](http://www.linux-usb.org/) needed to run `lsusb`

## Installation Instructions

### Option 1: NixOS with Home Manager (Recommended for NixOS users)

For NixOS users with Home Manager, you can use the included NixOS module for automatic systemd service management:

1. Import the module in your Home Manager configuration:
   ```nix
   { config, pkgs, ... }:
   {
     imports = [
       /path/to/yubilock/yubilock.nix
     ];

     services.yubilock = {
       enable = true;
       autoRestore = true;  # Automatically restore yubilock state on login
     };
   }
   ```

2. Copy the Waybar scripts to `~/.config/waybar/scripts/`:
   ```bash
   mkdir -p ~/.config/waybar/scripts/
   cp scripts/*.sh ~/.config/waybar/scripts/
   chmod +x ~/.config/waybar/scripts/*.sh
   ```

3. Add the custom module to your Waybar config (see [Waybar Configuration](#part-3-waybar-configuration)).

4. Add the CSS to your Waybar style.css (see [Waybar CSS Style](#part-4-waybar-css-style)).

5. Rebuild your NixOS configuration:
   ```bash
   home-manager switch
   ```

The systemd services will be automatically configured:
- `yubilock.service` - Monitors YubiKey presence and locks screen on removal
- `yubilock-restore.service` - Restores yubilock state on login (if `autoRestore = true`)

### Option 2: Manual Installation (All Linux distributions)
1. Save the three scripts to: `~/.config/waybar/scripts/`
2. Make them executable:
   ```
   chmod +x ~/.config/waybar/scripts/yubikey-status.sh
   chmod +x ~/.config/waybar/scripts/yubilock.sh
   chmod +x ~/.config/waybar/scripts/yubilock-toggle.sh
   ```
3. Add the custom module to your Waybar config (see [Waybar Configuration](#part-3-waybar-configuration)).
4. Add the CSS to your Waybar style.css and/or style it to your liking (see [Waybar CSS Style](#part-4-waybar-css-style)).
5. Restart Waybar: `killall waybar && waybar &`

Now you can toggle the Yubilock service by clicking the indicator in your Waybar. The indicator will show the current status of the service and whether a YubiKey is currently inserted.


## Part 3: Waybar Configuration
Add this to your Waybar configuration file:

3.1 For NixOS:
```nix
"custom/yubilock" = {
  return-type = "json";
  interval = 5;
  exec = "$HOME/.config/waybar/scripts/yubikey-status.sh";
  on-click = "$HOME/.config/waybar/scripts/yubilock-toggle.sh";
  tooltip = true;
  format = "{icon}";
  format-icons = {
    active = "";
    inactive = "";
  };
};
```
3.2 For other Linux distributions:
```json
"custom/yubilock": {
    "return-type": "json",
    "interval": 5,
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

## Part 4: Waybar CSS Style
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

#custom-yubilock.yubilock-off {
    background-color: #e74c3c;
    color: #ffffff;
}

#custom-yubilock.yubilock-on:hover,
#custom-yubilock.yubilock-off:hover {
    background-color: #2980b9;
}
```

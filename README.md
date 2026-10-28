# PD3VR-Mod
This profile utilizes UEVR's powerful injector to make Payday 3 VR support possible

(I'd like to point out the fact that this is very very WIP, I expect a ton of bugs and so should you. I do my best to add features and mitigate issues when I have enough free time so please be patient)

## Features
* Inverse Kinematics (IK)

* Full body visibility (optional)

* Weapon slot system 

* Throwables Support

* Animations support

* Two-handed weapon handling  

* Manual reloads, bolting, and magazine ejection

* Left-handed support

* Customizable aiming options, including HMD, right weapon, left weapon, and more

## Getting Started
--------

----------
1: Extract the profile, place it into '%appdata%/UnrealVRMod' (Create if needed)
(If your on a non steam version of payday 3, rename the profile to the payday 3 executable name located in your PAYDAY3\Binaries\Win64

2: Launch the game and start a heist

3: Open the UEVR Injector

4: Choose the payday 3 executable from the dropdown menu and press Inject

5: Wait a short bit, when your game freezes that means its injecting

6: after the game unfreezes. Look to your top-left and enable  *Show Advanced Menu*

7: Scroll down and you'll see a "PAYDAY3 VR" tab pop up, configure your settings there

(If you don't see the PAYDAY3 VR tab, go into Lua Loader ---> Main --> Check RigHandler.lua)

(Wait 2-3 seconds after injecting if your weapon animations are not calibrated, if it is not calibrated then the script will automatically swap weapons and initiate reloads, do not interfere)

8: after your done, close the menu by pressing  down on both joyticks and start playing



(Note: If you restart heists, you need to reset scripts through Lua Loader --> Main --> Reset Scripts)

# Credits:
(This project uses my modified fork of JoeyHodge's UEVR fork, which is based on Praydog's UEVR.)

(uses  a forked version of jbusfield's uevrlib)

**(fan-made UEVR profile, not affiliated with Starbreeze/Overkill)**

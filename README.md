# PD3-UEVR-Profile
This profile utilizes UEVR's powerful injector to make Payday 3 VR support possible

(FAQ introduced below)

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
## Legend for beginners:

Injector: Referring to PD3UEVRInjector (https://github.com/wesam12131/PD3VR-UEVR-Injector)

Profile:  referring to PAYDAY3-Win64-Shipping  (https://github.com/wesam12131/PD3VR/releases)

## Tutorial

1: Install and unzip  the [forked injector](https://github.com/wesam12131/PD3VR-UEVR-Injector)

2: Install the desired [profile version](https://github.com/wesam12131/PD3VR/releases) 

(ensure that the directory your installing in doesn't override the profile's name  to something like PAYDAY3-Win64-Shipping - Copy(1), if it happens, do rename it back to PAYDAY3-Win64-Shipping)

3: open the forked injector's exe, then press "import config" at the left-side menu and double click on the newly installed profile named PAYDAY3-Win64-Shipping

(If your on a non steam version of payday 3, rename the profile to the payday 3 executable name located in your PAYDAY3\Binaries\Win64)

4: Press Yes when it prompts you that it has DLLs. I plan to open source them aswell but they're mostly vibe-coded utility functions because lua can't do

5: Launch the game  and join a heist

6: Choose the payday 3 executable from the dropdown menu and press Inject

5: Wait a short bit, when your game freezes that means its injecting

6: after the game unfreezes. Look to your top-left and enable  *Show Advanced Menu*

7: Scroll down and you'll see a "PAYDAY3 VR" tab pop up, configure your settings there

(If you don't see the PAYDAY3 VR tab, go into Lua Loader ---> Main --> Check the box of RigHandler.lua)

(If you hear weapon swapping/reloading sounds almost right after enabling scripts/injection then wait for it to full finish because its calibrating animations)

8: after your done, close the menu by pressing  down on both joyticks and start playing

(Each heist start/restart you will need to head to the UEVR menu --> head to the section Lua Loader --> Scripts --> Reset scripts)

## FAQ:

Q: How do I grab my primary?

A: grip the back of your head once

Q:My camera spins like crazy 

A: Enable righandler.lua or disable then renable it

Q: My camera doesn't follow where I'm pointing

A: head to Lua loader --> PD3VR --> Change Movement orientation from the default (UEVR is default, in which it defaults to the game's) to something like HMD or controllers

Q: I encountered a bug, how do I report it?

A: I have a thread in FLAT2VR's server under #UE-Games, or DM me at @._wesam

# Credits:
(This project uses my modified fork of JoeyHodge's UEVR fork, which is based on Praydog's UEVR.)

(uses  a forked version of jbusfield's uevrlib)

**(fan-made UEVR profile, not affiliated with Starbreeze/Overkill)**

<div align="center">

[![Codacy Quality](https://app.codacy.com/project/badge/Grade/c4a01f22c3864d8c80b8c6891a6feb5f)](https://app.codacy.com/gh/quinncthirtyone/SessionTracker69/dashboard?utm_source=gh&utm_medium=referral&utm_content=&utm_campaign=Badge_grade)
[![GitHub commit activity](https://img.shields.io/github/commit-activity/m/quinncthirtyone/SessionTracker69?label=Commit%20Activity&color=%23073B4C)](https://github.com/quinncthirtyone/SessionTracker69/graphs/commit-activity)
[![GitHub issues](https://img.shields.io/github/issues/quinncthirtyone/SessionTracker69?label=Issues&color=%23118AB2)](https://github.com/quinncthirtyone/SessionTracker69/issues)

</div>

A lightweight PowerShell-based tray application for Windows that tracks time spent in various applications.

## Features
- #### Time and Session Tracking
    - Tracks play time for PC or emulated games.
    - **Session Tracking (including idle sessions)**
    - **Toggleable idle detection** to automatically pause tracking during inactivity.
    - Tracks new roms after registering any emulator.
    - HWiNFO64 integration to display session time and tracking status in its sensor panel.
- #### Profiles and UI
    - **Dual profiles** for multiple users or configurations.
    - **Simple and intuitive UI**.
    - **Quick View function to look at recent sessions and overall playtime stats on demand**.
    - Various detailed statistics and displays for gaming data.
    - Game status to indicate if the user has finished a game or are still playing.
- #### Performance
    - It is a compact app with minimal effect on performance.
    - User data stored in a transferable .db file for continuity across different machines.
    - Backups folder in case of accidental data corruption.

## Installation Instructions
1. Open a Powershell window as admin and run below command to allow powershell modules to load on your system. Choose `Yes` when prompted.
    - `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser`

2. Download ***SessionTracker.zip*** from the [latest release](https://github.com/quinncthirtyone/SessionTracker69/releases/latest).
3. Extract ***SessionTracker*** folder and Run `Install.bat`. Choose Yes/No for autostart at Boot.
4. Use the shortcut on desktop / start menu for launching the application.
5. Regularly backup your `SessionTracker.db` and `backups` folder to avoid data loss. Click ***Settings => Open Install Directory*** option in app menu to find them.

## Attributions
Built using

- [PSSQLite](https://www.powershellgallery.com/packages/PSSQLite) by [Warren Frame](https://github.com/RamblingCookieMonster)
- [ps12exe](https://github.com/steve02081504/ps12exe) by [Steve Green](https://github.com/steve02081504)
- [DOMPurify](https://github.com/cure53/DOMPurify) by [Cure53](https://github.com/cure53)
- [DataTables](https://datatables.net/)
- [Jquery](https://jquery.com/)
- [ChartJs](https://www.chartjs.org/)
- Various Icons from [Icons8](https://icons8.com)
- Game Cartridge Icon from [FreePik on Flaticon](https://www.flaticon.com/free-icons/game-cartridge)
- Based on [Gaming Gaiden](https://github.com/kulvind3r/gaminggaiden) by [kulvind3r](https://github.com/kulvind3r).

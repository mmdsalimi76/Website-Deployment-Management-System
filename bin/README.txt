# WEBSITE Portable Binaries
This folder contains the core binaries required for the application to be fully portable and air-gap ready.

### Local Tools (Windows)
These are used by this application to communicate with the VPS.
1. plink.exe (PuTTY Link) - [Included]
2. pscp.exe (PuTTY Secure Copy) - [Included]

### Remote Tools (Linux Static Binaries)
These are automatically sideloaded to the VPS if it lacks them.
3. rsync (Linux x86_64) - [Included]
4. unzip (Linux x86_64) - [Included]

The application is configured to prioritize these local tools over any system-wide installations.

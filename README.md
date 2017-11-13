# Chromebrew scripts
Useful bash utility scripts for Chrome/Chromium OS systems.

## Overview
[Neverware](https://www.neverware.com/) disables the ability to perform a [powerwash](https://support.google.com/chromebook/answer/183084?hl=en) in [CloudReady](https://www.neverware.com/#getcloudready) and [Google](https://www.google.com/) disables execute permissions on certain directories to protect [Chromium OS](https://www.chromium.org/chromium-os). These scripts are useful to [powerwash](https://support.google.com/chromebook/answer/183084?hl=en) your [Chromebook](https://www.google.com/chromebook/) and reset to the factory settings, install, remove or update [Chromebrew](https://github.com/skycocker/chromebrew) or remove rootfs verification and mount your filesystem to be read/write.

## WARNING
If used improperly, these scripts can render your system useless. Please proceed with caution and do not execute unless you know what you're doing. Review the `References` section below to understand the impact of the changes. As true of any open source software, I'm not responsible if you brick your system.

## Installation
```
$ git clone https://github.com/uberhacker/chromebrew-scripts
$ sudo cp chromebrew-scripts/* /usr/local/bin
```
## Usage
Install Chromebrew: `$ chromebrew -i | --install`

Remove Chromebrew: `$ chromebrew -r | --remove`

Update Chromebrew: `$ chromebrew -u | --update`

Reset to factory settings: `$ powerwash`

Remove rootfs verification: `$ rootfs`

Mount the filesystem read/write: `$ rw`

## References
- https://support.google.com/chromebook/answer/183084?hl=en
- https://neverware.zendesk.com/hc/en-us/articles/115000765287--Powerwash-via-the-cmd-line
- https://www.chromium.org/chromium-os/poking-around-your-chrome-os-device#TOC-Making-changes-to-the-filesystem
- https://sites.google.com/site/cr48ite/getting-technical/remove-rootfs-verification-make-read-write

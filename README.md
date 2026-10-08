## netboot.xyz-custom

Fork me!  This repo will allow you to create custom menus within netboot.xyz.
It works by using your github user name that you input and chains to this URL:

    https://raw.githubusercontent.com/${github_user}/netboot.xyz-custom/master/custom.ipxe

Once forked, you can edit the menu as much as you want.  You can compile the iPXE image to
set the `github_user` name early on so that your Github user name is set ahead of time and
will automatically display your custom submenu on boot.  You can also set your Github user
name from the Utilities menu (**Tools:** -> **Utilities** -> **netboot.xyz tools:**) which
will cause a custom menu to appear in the main menu.

If you are new to iPXE scripting, take a look at `custom.ipxe.example` and build up from that.

### Menu entries

- **Debian 13 + Protect Viewer kiosk:** unattended Debian install that boots into
  [unifi-protect-viewer](https://github.com/digital195/unifi-protect-viewer). The installer
  also works on its own on any existing Debian box. See [unifi-protect-viewer/](unifi-protect-viewer/README.md).

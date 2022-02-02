# DITA-ditaot-utilities

This is a collection of utilities intended to make it easier to work with the [DITA Open Toolkit](https://www.dita-ot.org/).

Although to be honest, there's only a single utility:

* `ditaot_install.sh` - install (or reinstall) the latest version of the DITA Open Toolkit

## Getting Started

You can run these utilities on a native linux machine, or on a Windows 10 machine that has Windows Subsystem for Linux (WSL) installed.

### Installing

Download or clone the repository, then put its `bin/` directory in your search path.

For example, in the default bash shell, add this line to your `~/.profile` file:

```
PATH=~/DITA-ditaot-utilities/bin:$PATH
```

## ditaot_install.sh

This is a bash script that checks the DITA-OT website for the latest version, then installs it:

![fresh installation](svg/ditaot_install_new.svg)

If the latest version is already installed, the script asks if it should be reinstalled:

![reinstallation](svg/ditaot_install_reinstall.svg)

This reinstallation can be useful if you've modified the DITA-OT to run experiments.

The script installs the DITA-OT in your home directory in a directory named after its version:

`~/dita-ot-<VERSION>`

In addition, a version-independent filesystem link is created at

`~/dita-ot`

so that you can put `~/dita-ot` in your `$PATH` and always get the latest version.

### Automatically Installing Plugins

If you have DITA-OT plugins to be installed, add the following to your `~/.profile` file to specify the list of plugins to install (exact syntax is important so that the entries are linefeed-separated-only, with no indenting):

```
# DITA-OT plugins for the ditaot_install.sh script to install
export DITAOT_PLUGINS_TO_INSTALL="\
/path/to/com.my.plugin1
/path/to/com.my.plugin2
/path/to/com.my.plugin3"
```

When this variable is defined, the script creates filesystem links to them in the `~/dita-ot-<VERSION>/plugins` directory, then runs `dita install` to install them.

## Author

My name is Chris Papademetrious. I'm a technical writer with [Synopsys Inc.](https://www.synopsys.com/), a semiconductor design and verification software company.

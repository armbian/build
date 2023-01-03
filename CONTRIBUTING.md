# Contributing to Armbian Linux build framework

We would love to have you join the Armbian community! Below summarizes the processes that we follow.

## Reporting issues

Before [reporting an issue](https://github.com/armbian/build/issues/new/choose), check our [backlog of open issues](https://github.com/armbian/build/issues) and [pull requests](https://github.com/armbian/build/pulls) to see if someone else has already reported or working on it. If an issues is already open, feel free to add your scenario, or additional information, to the discussion. Or simply "subscribe" to it to be notified when it is updated.

If you find a new issue with the project please let us hear about it! The most important aspect of a bug report is that it includes enough information for us to reproduce it. So, please include as much detail as possible and try to remove the extra stuff that does not really relate to the issue itself. The easier it is for us to reproduce it, the faster it will be fixed!

Please do not include any private/sensitive information in your issue! We are not responsible for your privacy, this is open source software.

## Working on issues

Once you have decided to contribute to Armbian by working on an issue, check our backlog of open (or [JIRA](https://armbian.atlassian.net/jira/dashboards/10000) issues open by the team) looking for any that do not have an "In Progress" label attached to it. Often issues will be assigned to someone, to be worked on at a later time. If you have the time to work on the issue now add yourself as an assignee, and set the "In Progress" label if you are a member of the “Containers” GitHub organization. If you can not set the label, just add a quick comment in the issue asking that the “In Progress” label be set and a member will do so for you.

Please be sure to review the [Development Code Review Procedures and Guidelines](https://docs.armbian.com/Development-Code_Review_Procedures_and_Guidelines/) as well before you begin.

## Contributing

This section describes how to start contributing to Armbian.

### Prepare your environment

* Create an Ubuntu 22.04 VM with VirtualBox or any other suitable hypervisor. 
* Install [Github CLI tool](https://github.com/cli/cli/blob/trunk/docs/install_linux.md)
* Configure git:

```bash
    git config --global user.email "your@email.com"
    git config --global user.name "Your Name"
```

* Generate GPG key

```bash
    gpg --generate-key
```

* Generate Github login [token](https://docs.github.com/en/free-pro-team@latest/github/authenticating-to-github/creating-a-personal-access-token)
* Login to Github (you only have to do the steps above once)

```bash
    gh auth login --with-token <<< 'your_token'
```

### Fork and clone Armbian

* Fork armbian/build, clone and add remote

```bash
    gh repo fork armbian/build --clone=true --remote=true
```

* Create branch

```bash
    cd build
    git checkout -b your_branch_name # change branch name for your patch
```

### Generate new patch template

* Compile Armbian (this use case is to change something in the device tree and test the built image)

```bash
    ./compile.sh CREATE_PATCHES="yes"
```

* Full OS image for flashing
* Do not change the kernel configuration
* Choose a board
* Choose a kernel
* Choose a release package base
* Choose image type
* Configuring apt-cacher-ng
* Wait for prompt to make u-boot changes (press Enter after making changes in specified directory)

```bash
    [ o.k. ] * [l][c] enable-distro-bootcmd.patch
    [ warn ] Make your changes in directory: [ /home/yourhome/build/cache/sources/u-boot-odroidxu/odroidxu4-v2017.05 ]
    [ warn ] Press <Enter> after you are done [ waiting ]
```

### Work on your patch

* Open another terminal or files window
* In this case I want to add gpio-line-names to the Odroid XU4 device tree when prompted to do so

  ```bash
    sudo nano build/cache/sources/linux-odroidxu4/odroid-5.4.y/arch/arm/boot/dts/exynos5420-pinctrl.dtsi
  ```

* Wait for prompt to make kernel changes (press Enter after making changes in specified directory)

  ```bash
    [ warn ] Make your changes in this directory: [ /home/yourhome/build/cache/sources/linux-odroidxu4/odroid-5.4.y ]
    [ warn ] Press <Enter> after you are done [ waiting ]
  ```

* Test the changes you made on your board
  * Mine was located in `/home/yourhome/build/output/images/Armbian_21.02.0-trunk_Odroidxu4_focal_current_5.4.83.img`
* Rename patch to something meaningful and move to proper location

  ```bash
    mv output/patch/kernel-odroidxu4-current.patch patch/kernel/odroidxu4-current/add-gpio-line-names.patch
  ```

Next, you can prepare to submit your patch to the Armbian project.

## Submitting pull requests

No Pull Request (PR) is too small! Typos, additional comments in the code, new test cases, bug fixes, new features, more documentation, ... everything is welcome!

While bug fixes can first be identified via an "issue", that is not required for things mentioned above. It is fine to just open up a PR with the fix, but make sure you include the same information you would have included in an actual issue - like how to reproduce it.

PRs for new features should include some background on what use cases the new code is trying to address. When possible and when it makes sense, try to break-up larger PRs into smaller parts - it is easier to [review](https://github.com/armbian/build/pulls?q=is%3Apr+is%3Aopen+review%3Arequired+label%3A%22Ready+%3Aarrow_right%3A%22) smaller code changes. But only if those smaller ones make sense as stand-alone PRs.

You should squash your commits into logical pieces of work that can be reviewed separate from the rest of the PRs. Squashing down to just one commit is ok as well, since in the end the entire PR will be reviewed anyway. If in doubt, squash.

### Describe your changes in commit messages

Describe your problem(s). Whether your patch is a one-line bug fix or 5000 lines including a new feature, there must be an underlying problem that motivated you to do this work. Your description should work to convince the reviewer that there is a problem worth fixing and that it makes sense for them to read past the first paragraph.  This means providing comprehensive details about the issue, including, but not limited to: 
* How the problem presented itself
* How to replicate the problem
* Provide 'dmesg' and/or 'armbianmonitor -u' output showing board used and any console output surrounding the issue
* Why you feel it is important for this issue to be resolved

## Communications

For general questions and discussion, please use the IRC `#armbian`, `#armbian-devel` or `#armbian-desktop` on Libera.Chat or [Discord server](http://discord.armbian.com). Most IRC and Discord channels are bridged and recorded.

For discussions around issues/bugs and features, you can use the [GitHub issues](https://github.com/armbian/build/issues), the [PR tracking system](https://github.com/armbian/build/pulls) or our [Jira ticketing system](https://armbian.atlassian.net/jira/software/c/projects/AR/issues/?filter=allissues).

## Other ways to contribute

* [Become a new board maintainer](https://docs.armbian.com/Board_Maintainers_Procedures_and_Guidelines/)
* [Apply for one of the position](https://forum.armbian.com/staffapplications/)
* [Help us covering costs](https://forum.armbian.com/subscriptions/)
* [Help community members in the Forum](https://forum.armbian.com/)
* [Check forum announcements section for any requests for help from the community](https://forum.armbian.com/forum/37-announcements/)

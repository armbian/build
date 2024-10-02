# Changelog

## [0.5.4] - 2018-11-05

### Changed

- Fixes a bug where a user set background from theme.conf.user wouldn't be read at all

## [0.5.4] - 2018-11-03

### Changed

- Fixes a bug where "FontPointSize" would not affect the size of the power buttons labels
- Added a new variable "Font" to hard set a specific font for your greeter
- Added the option "AvatarOutline"" to make your Avatar Image appear with an outline
- Options for the appearance of the outline: "AvatarOutlineColor" and "AvatarOutlineWidth"

## [0.5.3] - 2018-10-12

### Changed
- A lot of new options in theme.conf, see README for details

## [0.5.2] - 2018-07-22

### Changed
- Fixes a bug where power buttons hover area was off
- The background now draws in a seperate QML item, this hopefully fixes a black screen for some people

## [0.5.1] - 2018-06-16

### Changed
- Further improvement for the power buttons
- Sane blur defaults

## [0.5.0] - 2018-06-13

### Changed
- The whole theme got renamed to avoid confusion with the NixOS linux distribution
- Fixed the keyboard layout button label getting cut off. It is now image only
- The power buttons now also trigger when clicked on their respective labels
- The background blur can now be deactivated or altered in intensity with variables in the config file

## [0.4.1] - 2018-04-16

### Changed
- Fixed bug where the system icons won't work

## [0.4.0] - 2018-04-12

### Added
- MIT License
- GitHub Repository
- Changelog
- System icons now have a change in opacity when hovering over them

### Changed
- README is now more detailed and written in Markdown

## [0.3.0]

### Changed
- Fixed fonts now based on screen size
- Icons and password box dimensions based on screen size

## [0.2.0]

### Changed
- Font sizes

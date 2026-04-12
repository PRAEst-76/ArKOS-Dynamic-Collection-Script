## ArkOS / dArkOs Dynamic Collections Script

A bash script thrown together to scan [ArkOS](https://github.com/christianhaitian/arkos/) / [dArkOs](https://github.com/christianhaitian/dArkOS/) EmulationStation gamelists and generate custom genre collections.

It has only been tested on the [R36S](https://www.r36swiki.com) using [dArkOS](https://github.com/southoz/dArkOSRE-R36/) but should work on any EmulationStation-based OS with minimal tweaking. Forks and pull requests welcome.

Options
--install    Will install basic whitelist and genre map cfgs in ~/.esdynocol/
--dry-run    Will parse gameslist but not change anything
--diff        Will show the changes
--show-ignored    Will display unparsed/unknown/unwanted genres

Running without switches will initiate the standard genre collection creation.

### To do (possibly)

- Generate collections based on game series.
- Have it work on other Emulation Station-based systems that don't have automatic genre collections.
- Make it run from ES Options/Tools

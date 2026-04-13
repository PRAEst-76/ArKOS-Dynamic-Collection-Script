##### ArkOS / dArkOs Dynamic Collections script
*or*  
### EmulationStation Dynamic Collection script
*or*  

![Esdynocol](https://github.com/user-attachments/assets/3b5c6c74-1c13-46a8-a2a2-122e7854b75f)

A bash script to scan [ArkOS](https://github.com/christianhaitian/arkos/) / [dArkOs](https://github.com/christianhaitian/dArkOS/) EmulationStation gamelists and generate custom genre collections in /home/ark/.emulationstation/collections/

It has only been tested on the [R36S](https://www.r36swiki.com) using [dArkOS](https://github.com/southoz/dArkOSRE-R36/) but should work on any EmulationStation-based OS with minimal tweaking. Forks and pull requests welcome.


### Options

Some optional options...

`--dry-run`
> Parses gameslists but doesn't create genre collections.

`--diff`
> Shows the changes since the last run.

`--show-ignored`
> Display unparsed/unknown/unwanted genres to help in manually updating the genre_map.cfg and whitelist.cfg

Running without command line options will initiate the standard genre collection creation. If no existing genre map or whitelist are located in .config/esdynocol/ then they will be created there, along with a cache file.


### Additional files (automatically created)

The scripts creates some files in .config/esdynocol/

`whitelist.cfg`
> contains a list of the basic genres you want assigned so as not to fill your ES with multitudes of vague genres. By default it sticks to the basic ones supported by many themes, you can customise it to your preference.

`genre_map.cfg`
> a list of vague and sub-genres to map to basic theme genres. Again, can be tailored to your preference.

`cache.txt`
> Contains hashes of gameslists to determine if they have been changed and need reparsed.


### To do (possibly)

- Generate collections based on game series.
- Have it work on other Emulation Station-based systems that don't have automatic genre collections.
- Make it run from ES Options/Tools

# Multifunction clock made for [MicroMade's DSM-51](pliki.micromade.pl/pdf/dsm_kk.pdf)
#### Dependency
[sdcc](https://sourceforge.net/projects/sdcc/)
#### Compilation
```
sdcc clock.c
```
In order to use program on DSM-51 emulator you will need to compile the program with modified `sdcc`. 
This modification requires switching mcs51.lib library file attatched in this repository.
Usualy you can find this library in
```
/usr/share/sdcc/lib/small/mcs51.lib
```
Once that's done recompile the program and run `clock.ihx` with DSM-51 emulator.
### Features
- Setting time using multiplex keyboard arrows (edit mode)
- Sending commands via serial port
  - `set hh.mm.ss` - set the time in format hours.minutes.seconds
  - `get` - outputs curretn time to serial port
  - `edit` - enter edit mode 
  - Program is immune to incorrect commands, this will still be stored in history but will be labeled as ERR
- View serial port command history on LCD display use up and down arrow to scroll through history

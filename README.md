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
- Setting time using multiplex keyboard

  ![mux_keyboard](images/mux.gif?raw=true)
  - Left and right arrows - enter edit mode
  - Up and down arrrows - edit selected field's value (only in edit mode)
  - Enter - save changes
  - Esc - discard changes
- Sending commands via serial port (all commands case insensitive)

   settings for serial transmission - baudrate = 4800, bits between bytes 2, no parity bit
   ![commands](images/cmds.gif?raw=true)
  - `set hh.mm.ss` - set the time in format hours.minutes.seconds
  - `get` - outputs curretn time to serial port
  - `edit` - enter edit mode 
  - Program is immune to incorrect commands, those will still be stored in history but will be labeled as ERR
- View serial port command history on LCD display use up and down arrow keys on matrix keyboard to scroll through history
  ![mat_keyboard](images/mat.gif?raw=true)

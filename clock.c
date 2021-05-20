/* Serial transmission settings: baudrate == 4800; bits between bytes == 2; no parity bit*/
/* Program expects enter(\n) at the end of a command */
#include <8051.h>
// input/output devices addresses
// 7segment display select
__xdata unsigned char* CSDS = (__xdata unsigned char*) 0xFF30; 
// 7segment display buffer
__xdata unsigned char* CSDB = (__xdata unsigned char*) 0xFF38;
// matrix keyboard - keys 8 to F
__xdata unsigned char* CSKB1 = (__xdata unsigned char*) 0xFF22;
//LCD write command
__xdata unsigned char* LCDWC = (__xdata unsigned char*) 0xFF80;
//LCD wrtie data
__xdata unsigned char* LCDWD = (__xdata unsigned char*) 0xFF81;
//LCD read command
__xdata unsigned char* LCDRC = (__xdata unsigned char*) 0xFF82;
//LCD read data
__xdata unsigned char* LCDRD = (__xdata unsigned char*) 0xFF83;
//devices' bit addresses
__sbit __at(0x96) S7ON; //on/off seven segment display
__sbit __at(0x97) TLED; //TEST diode
__sbit __at(0xB5) MUXK; //mux keyboard state bit

//index 0-9 -> characters 0-9
//index 10-19 -> characters 0.-9.
__code unsigned char znaki[20] = {0b00111111, 0b00000110, 0b01011011,
																 	0b01001111, 0b01100110, 0b01101101, 
																	0b01111101, 0b00000111, 0b01111111, 
																	0b01101111, 0b10111111, 0b10000110,
																	0b11011011, 0b11001111, 0b11100110,
																	0b11101101, 0b11111101, 0b10000111,
																	0b11111111, 0b11101111};

//function labels
void refresh7Seg(void);
void seg7Init(void);
void timerSerialInit(void);
void lcdInit(void);
unsigned char rotateLeft(unsigned char x);
unsigned char rotateRight(unsigned char x);
void t0Interrupt(void) __interrupt(1);
void refreshTimeValuesFor7Seg(void);
void updateTime(void);
void obslugaKlawiaturyMat(void);
void obslugaKlawiaturyMux(void);
void recognizeCommand(void);
void obslugaSetCommand(void);
void obslugaGetCommand(void);
void lcdWait(void);
void lcdInit(void);
void lcdShiftDispl(void);
void sendCmdToHist(void);
void refreshLCD(void);
void sendStrToLCD(unsigned char iS);
void enterEditMode(void);
void toLowerCase(void);
//variables
//seven segment display variables
unsigned char wybranyWys; //chosen seven segment display bitwise
unsigned char iter7Seg; //seven segment displays' iterator
unsigned char data7seg[6]; //data for seven segment displays
//T0 counter ant time variables
int licznikT0inter; //T0 interrupt counter -- should go up to 900
unsigned char sekundy; //seconds passed
unsigned char minuty; //minuts passed
unsigned char godziny; //hours passed
unsigned char stareSekundy; //seconds - needed for edit mode
unsigned char stareMinuty; //minutes - needed for edit mode
unsigned char stareGodziny; //hours - needed for edit mode
unsigned char selector; //selector == 0; chosen seonds; == 1 minutes; == 2 hours
//keyboards variables
unsigned char kbd1; //matrix keyboard state (key 8 to F)
unsigned char kbdPoprz; //matix keyboard previous state (for comparison)
unsigned char kbdMux; //mux keyboard state
unsigned char kbdMuxPoprz; //previous mux keyboard state
//serial viarables
unsigned char recvBuff[14]; //receive buffor
unsigned char sendBuff[10]; //send buffor
unsigned char iRecvB; //receive buffor iterator
unsigned char iSendB; //send buffor iterator
unsigned char recognizeBuff[13]; //buffor with command transformed to lowercase
//command variables
__xdata __at(0x5000) unsigned char cmdHist[10][13]; //command history -- external RAM
__xdata __at(0x4500) unsigned char cmdStat[10]; //command status (1 - err; 0 - ok)
__code unsigned char ok[3] = {'O', 'K', '\0'}; //string OK
__code unsigned char err[4] = {'E', 'R', 'R', '\0'}; //string ERR
unsigned char curCmds; //how much cmds cunrrently in memory
unsigned char iLstCmd; //last command iterator
unsigned char iDspCmd; //displayed command iterator
signed char iWzgLast; //how much can we move relative to last command
//LCD variables
unsigned char lcdStan; //state of LCD
unsigned char i; //general use iterator
//used 69/80 bytes (General prupose)
//bit flags
__bit flagInterruptT0;
__bit flagSecondPassed;
__bit editMode;
__bit recvFlg;
__bit sendFlg;
__bit setFlg;
__bit getFlg;
__bit editFlg;
__bit errorFlg;
__bit wasErrorFlg;
__bit wasEditMode;
__bit rfrshLCD;
__bit comesFromCmd;
//used 13/128 bits (16-bit addressable register)

void main(void)
{
	lcdInit();
	seg7Init();
	timerSerialInit();
	while(1) {
		if(flagInterruptT0 == 1) { //we want to refresh only after interrupt from T0
			flagInterruptT0 = 0;
			
			//update time and data for seven segments displays
			updateTime();
			refreshTimeValuesFor7Seg();
			refresh7Seg();

			//handle matrix keyboard
			//if mux key pressed and in last loop rotation we allowed for handling
			if(MUXK && kbdMux == 0)
				obslugaKlawiaturyMux();
			//zezwol na obsluge klawisza jezeli nowy przycisk nie wcisniety
			//allow handling key if new key not pressed
			else if(!MUXK && kbdMux == kbdMuxPoprz)
				kbdMux = 0;

			//refresh LCD if needed, but only after entire 7 segment display have been refreshed
			if(rfrshLCD == 1 && iter7Seg == 5) {
				rfrshLCD = 0;
				refreshLCD();
				if(comesFromCmd == 1) {
					comesFromCmd = 0;
					iLstCmd++;
					if(iLstCmd == 10)
						iLstCmd = 0;
				}
			}

			//let's check commands flag
			//edit
			if(editFlg == 1 && iter7Seg == 5) {
				editFlg = 0;
				enterEditMode();
				sendCmdToHist();
			}

			//get
			if(getFlg == 1 && iter7Seg == 5) {
				getFlg = 0;
				obslugaGetCommand();
				iSendB = 0;
				sendCmdToHist();
			}

			//set
			if(setFlg == 1 && iter7Seg == 5) {
				setFlg = 0;
				obslugaSetCommand();
				sendCmdToHist();
			}

			//error comands handling
			if(errorFlg == 1 && iter7Seg == 5) {
				errorFlg = 0;
				wasErrorFlg = 1;
				sendCmdToHist();
			}
			//end of refreshing
		}
	
		//serial recieve interrupt handling
		if(recvFlg == 1) {
			recvFlg = 0;
			recvBuff[iRecvB] = SBUF; //capture character
			if(recvBuff[iRecvB] == 10) { //LF
				if(recvBuff[iRecvB - 1] == 13) { //CR now we have CR+LF
					if(iRecvB == 1) //skip redundant \n
						recvBuff[iRecvB - 1] = recvBuff[iRecvB] = ' ';
					else
						recognizeCommand();
					iRecvB = 0; //zero receive buffor iterator
				}
			}
			else
				iRecvB++;
			if(iRecvB > 13) { //buffer overflow we need to zero iterator
				iRecvB = 0;
			}
		}

		//serial transmit interrupt handling
		if(sendFlg == 1) {
			sendFlg = 0;
			if(iSendB < 9) {
				SBUF = sendBuff[iSendB];
				iSendB++;
			}
		}
	} //while
} //main

void enterEditMode(void)
{
	if(editMode == 0) {
		if(flagSecondPassed != 1)
			licznikT0inter = 0;
		editMode = 1;
		stareSekundy = sekundy;
		stareMinuty = minuty;
		stareGodziny = godziny;
	}
}

void refreshLCD(void)
{
	//we need to print 1 or 2 commands on display
	if(curCmds == 1) {
		sendStrToLCD(iDspCmd);
		//we are sending only 1 command, then shifting display by whole second row
		for(i = 0; i < 40; i++)
			lcdShiftDispl();
	}
	else if(curCmds > 1) {
		if(curCmds == 10 && iDspCmd == 0) {
			sendStrToLCD(iDspCmd);
			sendStrToLCD(9);
		}
		else {
			sendStrToLCD(iDspCmd);
			sendStrToLCD(iDspCmd - 1);
		}
	} //else if
} //refreshLCD

void sendStrToLCD(unsigned char iS)
{
	//print command
	for(i = 0; cmdHist[iS][i] != '\0'; i++) {
		lcdWait();
		*LCDWD = cmdHist[iS][i];
	}
	//print space and OK or ERR
	if(cmdStat[iS] == 1) { //error -> less spaces
		for( ; i < 13; i++) {
			lcdWait();
			*LCDWD = ' ';
		}
		for( ; i < 16; i++) {
			lcdWait();
			*LCDWD = err[i - 13];
		}
	}
	else { // no error -> more spaces
		for( ; i < 14; i++) {
			lcdWait();
			*LCDWD = ' ';
		}
		for( ; i < 16; i++) {
			lcdWait();
			*LCDWD = ok[i - 14];
		}
	}
	//shift to newline
	for( ; i < 40; i++)
		lcdShiftDispl();
}

void sendCmdToHist(void) {
	//write command to history
	for(i = 0; recvBuff[i] != 13; i++)
		cmdHist[iLstCmd][i] = recvBuff[i];
	cmdHist[iLstCmd][i] = '\0'; //end string char insted of \n
	if(wasErrorFlg == 1) {  //label command (1 - ERR, 0 - OK)
		wasErrorFlg = 0;
		cmdStat[iLstCmd] = 1;
	}
	else
		cmdStat[iLstCmd] = 0;
	//update cur cmd uterator to current
	iDspCmd = iLstCmd;
	iWzgLast = 0;
	if(curCmds < 10)
		curCmds++;
	//set refresh LCD flag and that it comes from command
	rfrshLCD = 1;
	comesFromCmd = 1;
} //this function sends cmd from recvBuff to cmd history and then sends it to LCD

void toLowerCase(void)
{
	//copy command from recvBuf to recognize buffor
	for(i = 0; recvBuff[i] != 13; i++)
		recognizeBuff[i] = recvBuff[i];
	recognizeBuff[i] = '\0';
	//transfrom to lowercase
	for(i = 0; recognizeBuff[i] != '\0'; i++)
		if(recognizeBuff[i] >= 'A' && recognizeBuff[i] <= 'Z') //32 to 'a' - 'A' ; 65 = 'A', 90 = 'Z'
			recognizeBuff[i] += 32;
}

void recognizeCommand(void)
{
	toLowerCase();
	if(recognizeBuff[0] == 's' && recognizeBuff[1] == 'e' && recognizeBuff[2] == 't' && recognizeBuff[3] == ' ' && recognizeBuff[6] == '.' && recognizeBuff[9] == '.' && recvBuff[12] == 13 && recvBuff[13] == 10)
		setFlg = 1;
	else if(recognizeBuff[0] == 'g' && recognizeBuff[1] == 'e' && recognizeBuff[2] == 't' && recvBuff[3] == 13 && recvBuff[4] == 10)
		getFlg = 1;
	else if(recognizeBuff[0] == 'e' && recognizeBuff[1] == 'd' && recognizeBuff[2] == 'i' && recognizeBuff[3] == 't' && recvBuff[4] == 13 && recvBuff[5] == 10)
		editFlg = 1;
	else
		errorFlg = 1;
	if(setFlg == 1) { //lets check if we recieved digits
		if(recvBuff[4] < 48 || recvBuff[4] > 57) { //it is not a digit
			setFlg = 0;
			errorFlg = 1;
		}
		if(recvBuff[5] < 48 || recvBuff[5] > 57) { //it is not a digit
			setFlg = 0;
			errorFlg = 1;
		}
		if(recvBuff[7] < 48 || recvBuff[7] > 57) { //it is not a digit
			setFlg = 0;
			errorFlg = 1;
		}
		if(recvBuff[8] < 48 || recvBuff[8] > 57) { //it is not a digit
			setFlg = 0;
			errorFlg = 1;
		}
		if(recvBuff[10] < 48 || recvBuff[10] > 57) { //it is not a digit
			setFlg = 0;
			errorFlg = 1;
		}
		if(recvBuff[11] < 48 || recvBuff[11] > 57) { //it is not a digit
			setFlg = 0;
			errorFlg = 1;
		}
	}
}

void obslugaSetCommand(void) {
	if(editMode == 1)
		wasEditMode = 1;
	else
		editMode = 1;
	//begin counting second from 0
	if(flagSecondPassed != 1)
		licznikT0inter = 0;
	//save old values
	stareSekundy = sekundy;
	stareMinuty = minuty;
	stareGodziny = godziny;
	godziny = minuty = sekundy = 0;
	//transfrom cmd from ASCII to integers
	godziny = (recvBuff[4] - 48) * 10 + (recvBuff[5] - 48);
	minuty = (recvBuff[7] - 48) * 10 + (recvBuff[8] - 48);
	sekundy = (recvBuff[10] - 48) * 10 + (recvBuff[11] - 48);
	if(godziny > 23 || minuty > 59 || sekundy > 59) { //incorrect time entered
		wasErrorFlg = 1;
		godziny = stareGodziny;
		minuty = stareMinuty;
		sekundy = stareSekundy;
	}
	if(wasEditMode == 1)
		wasEditMode = 0;
	else
		editMode = 0;
}

void obslugaGetCommand(void)
{
	sendBuff[2] = sendBuff[5] = '.';
	sendBuff[0] = (godziny / 10) + 48;
	sendBuff[1] = godziny % 10 + 48;
	sendBuff[3] = (minuty / 10) + 48;
	sendBuff[4] = minuty % 10 + 48;
	sendBuff[6] = (sekundy / 10) + 48;
	sendBuff[7] = sekundy % 10 + 48;
	sendBuff[8] = 13; //carriage return
	sendBuff[9] = 10; //new line
	iSendB = 0;
	sendFlg = 1;
}

void updateTime(void)
{
	//update time
	if(flagSecondPassed == 1) { //counted 1 second
		flagSecondPassed = 0;
		licznikT0inter -= 900;
		sekundy++;
		if(sekundy == 60) {
			minuty++;
			sekundy = 0;
			if(minuty == 60) {
				godziny++;
				minuty = 0;
				if(godziny == 24)
					godziny = 0;
			}
		}
	}
} //this function updates time values

void refreshTimeValuesFor7Seg(void)
{
	if(iter7Seg == 0) {//refreshing second units
		if(editMode == 1 && selector == 0) //we need a character with a dot 
			data7seg[0] = sekundy % 10 + 10;
		else
			data7seg[0] = sekundy % 10;
	}
	else if(iter7Seg == 1) { //refreshing second dozens
		if(editMode == 1 && selector == 0) //we need a char with a dot
			data7seg[1] = (unsigned char)(sekundy / 10) + 10;
		else
			data7seg[1] = (unsigned char)(sekundy / 10);
	}
	else if(iter7Seg == 2) { //refreshing minut units
		if(editMode == 1 && selector == 1)
			data7seg[2] = minuty % 10 + 10;
		else
			data7seg[2] = minuty % 10;
	}
	else if(iter7Seg == 3) { //refreshing minut dozens
		if(editMode == 1 && selector == 1)
			data7seg[3] = (unsigned char)(minuty / 10) + 10;
		else
			data7seg[3] = (unsigned char)(minuty / 10);
	}
	else if(iter7Seg == 4) { //refreshing hours units
		if(editMode == 1 && selector == 2)
			data7seg[4] = godziny % 10 + 10;
		else
			data7seg[4] = godziny % 10;
	}
	else if(iter7Seg == 5) { //refreshing hours dozens
		if(editMode == 1 && selector == 2)
			data7seg[5] = (unsigned char)(godziny / 10) + 10;
		else
			data7seg[5] = (unsigned char)(godziny / 10);
	}
} //this functions refreshes data to be sent fo seven segment displays

void lcdInit(void)
{
	rfrshLCD = comesFromCmd = 0;
	//clear refresh flag and iterators
	iDspCmd = iLstCmd = curCmds = 0;
	//clear LCD
	lcdWait();
	*LCDWC = 0b00000001;
	//set LCD functionality
	//use 8bit data bus, use 2 lines, resolution 5x7
	lcdWait();
	*LCDWC = 0b00111000;
	//display control
	//display data from memory without coursor and blinking
	lcdWait();
	*LCDWC = 0b00001100;
	//data input mode settings
	//increment mode ON, bez shiftowania
	lcdWait();
	*LCDWC = 0b00000110;
}

void seg7Init(void)
{
	unsigned char i;
	wybranyWys = 0b00000001;
	iter7Seg = 0;
	for(i = 0; i < 6; i++)
		data7seg[i] = 0;
}

void timerSerialInit(void)
{
	//Serial port configuration
	SCON = 0b01010000; //M0=0, M1=1, M2=0, REN=1, TB8=0, RB8=0, TI=0, RI=0
	//Serial port works in mode 1 -- we need to configure T1 counter
	TMOD = 0b00100001;
	//timer1: gate1=0, ct1=0, t1m1=1, t1m0=0 -- mode 2 (8bit TL1, reload TH1)
	//timer0: gate0=0, ct0=0, t0m1=0, t0m0=1 -- mode 1 (16bit TH0 + TL0)
	PCON &= 0b01111111; //setting SMOD to 0

	TH0 = 252; //we want to realod T0 four times -- this will give us 900 interrupts per second
	TL0 = 0;
	TH1 = 250; //this ensures we get baudrate == 4800
	TL1 = 250; //for timer 1 (together with SMOD == 0)
	TR0 = 1; //run timer 0 
	TR1 = 1; //run timer 1
	TF1 = 0; //clear timer1 overflow

	ET0 = 1; //allow interrupts from timer 0
	ES = 1; //allow interrupts from serial port
	EA = 1; //allow interrupts

	//starting values
	licznikT0inter = 0; //it counts to 900 and it is initialized with 0
	sekundy = 0;
	minuty = 0;
	godziny = 0;
	flagInterruptT0 = flagSecondPassed = editMode = 0;
	selector = 0;

	kbdMux = kbdMuxPoprz = kbd1 = kbdPoprz = 0;
	//making sure that iterators and flags are zeroed
	iRecvB = iSendB = i = 0;
	recvFlg = sendFlg = 0;
	RI = TI = 0;
	getFlg = setFlg = editFlg = errorFlg = wasErrorFlg = editMode = 0;
} //initializing timers(and their interrupts) and serial port

void lcdShiftDispl(void)
{
	lcdWait();
	*LCDWC = 0b00010100;
} //shifting displayed LCD field by 1 to the right

void lcdWait(void)
{
	lcdStan = *LCDRC;
	lcdStan &= 0b10000000;
	while(lcdStan != 0) {
		lcdStan = *LCDRC;
		lcdStan &= 0b10000000;
	}
} //wait for LCD to be ready for commands

void t0Interrupt(void) __interrupt(1)
{
	TH0 = 252; //reload TH0
	flagInterruptT0 = 1; //signalize interrupt
	if(editMode == 0)
		licznikT0inter++;
	if(licznikT0inter >= 900) {
		flagSecondPassed = 1;
	}
} //timer 0 interrupt handling

void serialInterrupt(void) __interrupt(4) __using(2) //using 2(bank) to save PSW register from overflowing
{
	if(RI == 1) {
		RI = 0;
		recvFlg = 1;
	}
	if(TI == 1) {
		TI = 0;
		sendFlg = 1;
	}
} //serial port interrupt handling

void obslugaKlawiaturyMat(void)
{
	//handling only up and down arrows
	if(kbd1 & 0b00100000) { //up arrow (C)
		if(curCmds > 2) {
			if(curCmds == 10) {
				if(iWzgLast >= 0) {
					if(iDspCmd == 9) {
						iDspCmd = 0;
					}
					else {
						iDspCmd++;
					}
					iWzgLast--;
				}
			}
			else {
				if(iDspCmd < curCmds) {
					iDspCmd++;
				}
			}
//			rfrshLCD = 1;
		}
	}

	if(kbd1 & 0b00010000) { //down arrow (D)
		if(curCmds > 2) {
			if(curCmds == 10) {
				if(iWzgLast < 8) {
					if(iDspCmd == 0)
						iDspCmd = 9;
					else
						iDspCmd--;
					iWzgLast++;
				}
			}
			else {
				if(iDspCmd > 1)
					iDspCmd--;
			}
			rfrshLCD = 1;
		}
	}
}

void obslugaKlawiaturyMux(void)
{
	//check which key to handle
	kbdMux = kbdMuxPoprz;
	if(kbdMux == 0b00000001) { // Enter (save changes)
		if(editMode == 1)
			editMode = 0;
	}
	if(kbdMux == 0b00000010) { //Esc (discard changes)
		if(editMode == 1) {
			sekundy = stareSekundy;
			minuty = stareMinuty;
			godziny = stareGodziny;
			editMode = 0;
		}
	}
	if(kbdMux == 0b00000100) { // ->
		enterEditMode();
		if(selector == 0)
			selector = 2;
		else
			selector--;
	}
	if(kbdMux == 0b00100000) { // <-
		enterEditMode();
		if(selector == 2)
			selector = 0;
		else
			selector++;
	}
	if(kbdMux == 0b00001000) { // ^ (up arrow)
		if(editMode == 1) {
			if(selector == 0) {
				sekundy++;
				if(sekundy == 60)
					sekundy = 0;
			}
			else if(selector == 1) {
				minuty++;
				if(minuty == 60)
					minuty = 0;
			}
			else if(selector == 2) {
				godziny++;
				if(godziny == 24)
					godziny = 0;
			}
		}
	}
	if(kbdMux == 0b00010000) { // V (down arrow)
		if(editMode == 1) {
			if(selector == 0) {
				if(sekundy == 0)
					sekundy = 59;
				else
					sekundy--;
			}
			else if(selector == 1) {
				if(minuty == 0)
					minuty = 59;
				else
					minuty--;
			}
			else if(selector == 2) {
				if(godziny == 0)
					godziny = 23;
				else
				godziny--;
			}
		}
	}
} //mux keyboard handling

void refresh7Seg(void)
{
	//matrix keyboard handling
	kbd1 = *CSKB1;
	if(kbd1 != kbdPoprz)
		obslugaKlawiaturyMat();
	kbdPoprz = *CSKB1;
	
	//refresh seven segment displays
	S7ON = 1; //turning displays off
	*CSDS =  wybranyWys;
	*CSDB = znaki[data7seg[iter7Seg]];
	S7ON = 0; //turning displays on

	//remember mux keyboard state
	kbdMuxPoprz = wybranyWys;

	//next loop rotation preparations
	iter7Seg++;
	wybranyWys = rotateLeft(wybranyWys);
	if(iter7Seg > 5) { //we have refreshed all seven segment displays
		iter7Seg = 0;
		wybranyWys = 0b00000001;
	}
} /* this functions refreshes seven segment displays, LED diodes
	 * and checking matrix keyboard state
	 */

unsigned char rotateLeft(unsigned char x)
{
	unsigned char tmp = x;
	x = (tmp << 1) | (tmp >> 7);
	return x;
} //this functions shits bits of x by one to the left

unsigned char rotateRight(unsigned char x)
{
	unsigned char tmp = x;
	x = (tmp >> 1) | (tmp << 7);
	return x;
} //this functions shifts bits of x by one to the right

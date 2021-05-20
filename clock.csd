/* Ustawienia transmisji szeregowej: baudrate == 4800; bity miedzy bajtami == 2; brak bitu parzystosci*/
/* Przy wysylaniu rozkazow program oczekuje na koncu na enter */
#include <8051.h>
// adresy urządzeń wejścia/wyjścia
// 7segment display select
__xdata unsigned char* CSDS = (__xdata unsigned char*) 0xFF30; 
// 7segment display buffer
__xdata unsigned char* CSDB = (__xdata unsigned char*) 0xFF38;
// klawiatura matrycowa klawisze od 8 do F 
__xdata unsigned char* CSKB1 = (__xdata unsigned char*) 0xFF22;
//LCD write command - wpis rozkazow na LCD
__xdata unsigned char* LCDWC = (__xdata unsigned char*) 0xFF80;
//LCD wrtie data - wpis danych na LCD
__xdata unsigned char* LCDWD = (__xdata unsigned char*) 0xFF81;
//LCD read command - odczyt stanu z LCD
__xdata unsigned char* LCDRC = (__xdata unsigned char*) 0xFF82;
//LCD read data - odczyt danych z LCD
__xdata unsigned char* LCDRD = (__xdata unsigned char*) 0xFF83;
//adresy bitów urządzeń
__sbit __at(0x96) S7ON; //bit przelączania wyświetlacza 7 sementowego
__sbit __at(0x97) TLED; //bit diody TEST
__sbit __at(0xB5) MUXK; //bit stan klawiatury MUX

//od 0 do 9 znaki zwykle od 0 do 9
//od 10 do 19 znaki z kropka od 0. do 9.
__code unsigned char znaki[20] = {0b00111111, 0b00000110, 0b01011011,
																 	0b01001111, 0b01100110, 0b01101101, 
																	0b01111101, 0b00000111, 0b01111111, 
																	0b01101111, 0b10111111, 0b10000110,
																	0b11011011, 0b11001111, 0b11100110,
																	0b11101101, 0b11111101, 0b10000111,
																	0b11111111, 0b11101111};

//etykiety funkcji
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
//zmienne
//zmienne data7segietlacza mux
unsigned char wybranyWys; //wybrany data7segietlacz bitowo
unsigned char iter7Seg; //index do iteracji po data7segietlaczach
unsigned char data7seg[6]; //tabela przechowująca dane do wyświetlania na wyś. 7seg.
//zmienne licznika T0 i czasowe
int licznikT0inter; //licznik przerwań ukladu T0 -- powinień liczyć do 900
unsigned char sekundy; //liczba sekund, które upłynęły
unsigned char minuty; //liczba minut, ktore uplynely
unsigned char godziny; //liczba godzin, ktore uplynely
unsigned char stareSekundy; //liczba sekund potrzebne do edit mode
unsigned char stareMinuty; //liczba minut potrzebne do edit mode
unsigned char stareGodziny; //liczba godzin potrzebne do edit mode
unsigned char selector; //selector == 0; wybrane sekundy; == 1 minuty; == 2 godziny
//zmienne klawiatur
unsigned char kbd1; //zmienna przyjmująca stan klawiatury klawisze 8..F
unsigned char kbdPoprz; //poprzedni stan klawiatury (dla porównywania)
unsigned char kbdMux; //stan klawiatury mux
unsigned char kbdMuxPoprz; //poprzedni stan klawiatury mux
//zmienne serial
unsigned char recvBuff[14]; //bufor odbierania
unsigned char sendBuff[10]; //bufor nadawania
unsigned char iRecvB; //iterator bufora odbierania
unsigned char iSendB; //iterator bufora nadawania
unsigned char recognizeBuff[13]; //bufor ktory zawiera komende tylko z malymi literami (do rozpoznawania)
//zmienne do przechowywania komend
__xdata __at(0x5000) unsigned char cmdHist[10][13]; //historia komend zapisywana w zewnentrznej pamieci RAM
__xdata __at(0x4500) unsigned char cmdStat[10]; //status komend (1 - err; 0 - ok)
__code unsigned char ok[3] = {'O', 'K', '\0'}; //string OK
__code unsigned char err[4] = {'E', 'R', 'R', '\0'}; //string ERR
unsigned char curCmds; //ile obecnie komend w historii zapisanych
unsigned char iLstCmd; //iterator ostatniej komendy
unsigned char iDspCmd; //iterator displayed command - iterator wyswietlanej komendy
signed char iWzgLast; //iterator ktory mowi nam ile komend mozemy pojsc do przodu/tylu wzgledem obecnej cmd
//zmienne dla LCD
unsigned char lcdStan;
unsigned char i; //iterator do zastosowan ogolnych
//uzyte 69/80 bajtow (General prupose)
//flagi bitowe
__bit flagInterruptT0; //flaga przerwania
__bit flagSecondPassed; //flaga miniecia 1 sekundy
__bit editMode; //flaga trybu edycji
__bit recvFlg; //recieve flag
__bit sendFlg; //send flag
__bit setFlg; //flaga komendy set
__bit getFlg; //flaga komendy get
__bit editFlg; //flaga komendy edit
__bit errorFlg; //flaga blednej komendy
__bit wasErrorFlg; //jezeli byla bledna komenda
__bit wasEditMode; //flaga informujaca nas czy edit mode jest juz ustawiony podczas komendy set
__bit rfrshLCD; //flaga mowiaca nam ze mamy odswiezyc LCD
__bit comesFromCmd; //flaga mowiaca nam ze mamy odswiezyc LCD pochodzaca od nadejscia komendy
//uzyte 13/128 bitow (16-bit addressable register)

void main(void)
{
	lcdInit();
	seg7Init();
	timerSerialInit();
	while(1) {
		if(flagInterruptT0 == 1) { //chcemy odświeżać tylko gdy jest przerwanie
			flagInterruptT0 = 0;
			
			//zaktualizuj czas, wartosci dla wyswietlacza 7seg oraz odswiez 7seg
			updateTime();
			refreshTimeValuesFor7Seg();
			refresh7Seg();

			//obsluz klawiature multipleksowana
			//jezeli mux ma wcisniety przycisk i w poprzednim obrocie zezwolilismy na obsluge
			if(MUXK && kbdMux == 0)
				obslugaKlawiaturyMux();
			//zezwol na obsluge klawisza jezeli nowy przycisk nie wcisniety
			else if(!MUXK && kbdMux == kbdMuxPoprz)
				kbdMux = 0;

			//odswiez LCD jezeli zaszla taka potrzeba, ale tylko gdy zostanie odswiezony caly wyswietlacz 7seg
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

			//sprawdzmy teraz flagi komend
			//obsluga edit
			if(editFlg == 1 && iter7Seg == 5) {
				editFlg = 0;
				enterEditMode();
				//wyslij komende do historii
				sendCmdToHist();
			}

			//obsluga get
			if(getFlg == 1 && iter7Seg == 5) {
				getFlg = 0;
				obslugaGetCommand();
				iSendB = 0;
				//trzeba cos poprawic, get znaczaco opoznia zliczanie czasu
				//wyslij komende do historii
				sendCmdToHist();
			}

			//obsluga set
			if(setFlg == 1 && iter7Seg == 5) {
				setFlg = 0;
				obslugaSetCommand();
				//wyslij komende do historii
				sendCmdToHist();
			}

			//obsluga blednych komend
			if(errorFlg == 1 && iter7Seg == 5) {
				errorFlg = 0;
				wasErrorFlg = 1;
				sendCmdToHist();
			}
			//koniec odswiezan
		}
	
		//obsluzmy przerwanie od serial recieve
		if(recvFlg == 1) {
			recvFlg = 0;
			recvBuff[iRecvB] = SBUF; //odbierz znak
			if(recvBuff[iRecvB] == 10) { //znak LF
				if(recvBuff[iRecvB - 1] == 13) { //znak CR (w sumie mamy CR+LF
					if(iRecvB == 1) //pomin nadmiarowy enter
						recvBuff[iRecvB - 1] = recvBuff[iRecvB] = ' ';
					else
						recognizeCommand();
					iRecvB = 0; //wyzeruj iterator bufora
				}
			}
			else
				iRecvB++;
			if(iRecvB > 13) { //przekraczamy bufor, trzeba wyzerowac iterator
				iRecvB = 0;
			}
		}

		//obsluzmy przerwanie od serial transmit
		if(sendFlg == 1) {
			sendFlg = 0;
			if(iSendB < 9) {
				SBUF = sendBuff[iSendB];
				iSendB++;
			}
		} //koniec obslugi nadawania serial
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
	//musimy wypisać 1 albo 2 komendy na wyświetlaczu
	if(curCmds == 1) {
		sendStrToLCD(iDspCmd);
		//wysylamy tylko 1 komende, przesun wyswietlacz o caly drugi rzad
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
	//wypisz komende
	for(i = 0; cmdHist[iS][i] != '\0'; i++) {
		lcdWait();
		*LCDWD = cmdHist[iS][i];
	}
	//wypisz spacje i znak OK lub ERR
	if(cmdStat[iS] == 1) { //jest error -> mniej spacji
		for( ; i < 13; i++) {
			lcdWait();
			*LCDWD = ' ';
		}
		for( ; i < 16; i++) {
			lcdWait();
			*LCDWD = err[i - 13];
		}
	}
	else { // nie ma error -> wiecej spacji
		for( ; i < 14; i++) {
			lcdWait();
			*LCDWD = ' ';
		}
		for( ; i < 16; i++) {
			lcdWait();
			*LCDWD = ok[i - 14];
		}
	}
	//przesun do nowej linii
	for( ; i < 40; i++)
		lcdShiftDispl();
}

void sendCmdToHist(void) {
	//przepisz komende do historii
	for(i = 0; recvBuff[i] != 13; i++)
		cmdHist[iLstCmd][i] = recvBuff[i];
	cmdHist[iLstCmd][i] = '\0'; //znak konca linii zamiast entera
	if(wasErrorFlg == 1) {  //daj etykiete komendzie (1 - ERR, 0 - OK)
		wasErrorFlg = 0;
		cmdStat[iLstCmd] = 1;
	}
	else
		cmdStat[iLstCmd] = 0;
	//zmien iterator wyswietlanych komend na obecna
	iDspCmd = iLstCmd;
	iWzgLast = 0;
	if(curCmds < 10)
		curCmds++;
	//i ustaw flage oswiezenia LCD oraz tego ze pochodzi od komendy
	rfrshLCD = 1;
	comesFromCmd = 1;
} //ta wysyla komende z recvBuff do historii komend na następnie wysyła ją na wyświetlacz

void toLowerCase(void)
{
	//najpierw skopiuj komende z bufera odbiornika do bufera rozpoznawacza
	for(i = 0; recvBuff[i] != 13; i++)
		recognizeBuff[i] = recvBuff[i];
	recognizeBuff[i] = '\0';
	//teraz jeżeli jest wielka litera zamien ja na mala
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
	if(setFlg == 1) { //sprawdzimy czy na pewno zostaly wyslane cyfry
		if(recvBuff[4] < 48 || recvBuff[4] > 57) { //to nie jest cyfra
			setFlg = 0;
			errorFlg = 1;
		}
		if(recvBuff[5] < 48 || recvBuff[5] > 57) { //to nie jest cyfra
			setFlg = 0;
			errorFlg = 1;
		}
		if(recvBuff[7] < 48 || recvBuff[7] > 57) { //to nie jest cyfra
			setFlg = 0;
			errorFlg = 1;
		}
		if(recvBuff[8] < 48 || recvBuff[8] > 57) { //to nie jest cyfra
			setFlg = 0;
			errorFlg = 1;
		}
		if(recvBuff[10] < 48 || recvBuff[10] > 57) { //to nie jest cyfra
			setFlg = 0;
			errorFlg = 1;
		}
		if(recvBuff[11] < 48 || recvBuff[11] > 57) { //to nie jest cyfra
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
	//zacznij zliczac sekunde od 0
	if(flagSecondPassed != 1)
		licznikT0inter = 0;
	//zapisz stare wartosci
	stareSekundy = sekundy;
	stareMinuty = minuty;
	stareGodziny = godziny;
	godziny = minuty = sekundy = 0;
	//zamien komende ascii na liczby
	godziny = (recvBuff[4] - 48) * 10 + (recvBuff[5] - 48);
	minuty = (recvBuff[7] - 48) * 10 + (recvBuff[8] - 48);
	sekundy = (recvBuff[10] - 48) * 10 + (recvBuff[11] - 48);
	if(godziny > 23 || minuty > 59 || sekundy > 59) { //zostala wpisana bledna godzina
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
	//aktualizacja czasu
	if(flagSecondPassed == 1) { //odmieżono sekunde
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
} //funkcja zajmuje sie aktualizacja wartosci czasu

void refreshTimeValuesFor7Seg(void)
{
	if(iter7Seg == 0) {//odswiezamy jednosci sekund
		if(editMode == 1 && selector == 0) //wtedy dajemy liczbe z kropka
			data7seg[0] = sekundy % 10 + 10;
		else
			data7seg[0] = sekundy % 10;
	}
	else if(iter7Seg == 1) { //odswiezamy dziesiatki sekund
		if(editMode == 1 && selector == 0) //wtedy dajemy liczbe z kropka
			data7seg[1] = (unsigned char)(sekundy / 10) + 10;
		else
			data7seg[1] = (unsigned char)(sekundy / 10);
	}
	else if(iter7Seg == 2) { //odswiezamy jednosci minut
		if(editMode == 1 && selector == 1) //wtedy dajemy liczbe z kropka
			data7seg[2] = minuty % 10 + 10;
		else
			data7seg[2] = minuty % 10;
	}
	else if(iter7Seg == 3) { //odswiezamy dziesiatki minut
		if(editMode == 1 && selector == 1) //wtedy dajemy liczbe z kropka
			data7seg[3] = (unsigned char)(minuty / 10) + 10;
		else
			data7seg[3] = (unsigned char)(minuty / 10);
	}
	else if(iter7Seg == 4) { //odswiezamy jednosci godzin
		if(editMode == 1 && selector == 2) //wtedy dajemy liczbe z kropka
			data7seg[4] = godziny % 10 + 10;
		else
			data7seg[4] = godziny % 10;
	}
	else if(iter7Seg == 5) { //odswiezamy dziesiatki godzin
		if(editMode == 1 && selector == 2) //wtedy dajemy liczbe z kropka
			data7seg[5] = (unsigned char)(godziny / 10) + 10;
		else
			data7seg[5] = (unsigned char)(godziny / 10);
	}
} //funkcja ta zajmuje sie odswiezaniem wartosci dla data7segietlaczy 7seg

void lcdInit(void)
{
	rfrshLCD = comesFromCmd = 0;
	//wyczyść flage refresh i iteratory
	iDspCmd = iLstCmd = curCmds = 0;
	//wyczyść lcd
	lcdWait();
	*LCDWC = 0b00000001;
	//ustaw funkcjonowanie wyświetlacza
	//uzywaj magistrali 8bitow, uzywaj 2 linii, rozdzielczosc punktowa 5x7
	lcdWait();
	*LCDWC = 0b00111000;
	//display control
	//wyswietlaj dane z pamieci bez kursora i bez migania
	lcdWait();
	*LCDWC = 0b00001100;
	//ustawienia trybu wejscia danych
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
	//Konfiguracja portu szeregowego
	SCON = 0b01010000; //M0=0, M1=1, M2=0, REN=1, TB8=0, RB8=0, TI=0, RI=0
	//Praca portu transmisji szeregowej w trybie 1 wymaga skonfigurowania T1
	TMOD = 0b00100001;
	//timer1: gate1=0, ct1=0, t1m1=1, t1m0=0 -- tryb 2 (8bit TL1, reload TH1)
	//timer0: gate0=0, ct0=0, t0m1=0, t0m0=1 -- tryb 1 (16bit TH0 + TL0)
	PCON &= 0b01111111; //ustawiamy SMOD na 0

	TH0 = 252; //chcemy przepełniać TH0 4 razy -- da to 900 przepełnień na sekundę
	TL0 = 0; //TL0 ma być na 0
	TH1 = 250; //chcemy zeby baudrate byl == 4800 wiec takie wartosci potrzebne
	TL1 = 250; //dla timera 1 (razem z SMOD == 0)
	TR0 = 1; //uruchom timer 0
	TR1 = 1; //uruchom timer 1
	TF1 = 0; //clear timer1 overflow

	ET0 = 1; //zezwól na przerwania od timera 0
	ES = 1; //zezwol na przerwania od portu szeregowego
	EA = 1; //zezwól na przerwania ogólnie

	//wartosci poczatkowe
	licznikT0inter = 0; //licznikT0inter zlicza do 900 i jest inicjalizowany zerem
	sekundy = 0;
	minuty = 0;
	godziny = 0;
	flagInterruptT0 = flagSecondPassed = editMode = 0;
	selector = 0;

	kbdMux = kbdMuxPoprz = kbd1 = kbdPoprz = 0;
	//upewniamy sie ze iteratori i flagi sa wyzerowane
	iRecvB = iSendB = i = 0;
	recvFlg = sendFlg = 0;
	RI = TI = 0;
	getFlg = setFlg = editFlg = errorFlg = wasErrorFlg = editMode = 0;
} //inicjalizacja timerów (i ich przerwań) oraz portu szeregowego

void lcdShiftDispl(void)
{
	lcdWait();
	*LCDWC = 0b00010100;
} //przesuwanie wyswietlanego pola LCD w prawo o 1

void lcdWait(void)
{
	lcdStan = *LCDRC;
	lcdStan &= 0b10000000;
	while(lcdStan != 0) {
		lcdStan = *LCDRC;
		lcdStan &= 0b10000000;
	}
} //oczekiwanie na gotowość LCD

void t0Interrupt(void) __interrupt(1)
{
	TH0 = 252; //przeładuj TH0
	flagInterruptT0 = 1; //zasygnalizuj przerwanie
	if(editMode == 0)
		licznikT0inter++;
	if(licznikT0inter >= 900) {
		flagSecondPassed = 1;
	}
} //obsługa przerwania timera 0

void serialInterrupt(void) __interrupt(4) __using(2) //using 2(bank) zeby zabespieczyc rejestr PSW przed nadpisaniem
{
	if(RI == 1) {
		RI = 0;
		recvFlg = 1;
	}
	if(TI == 1) {
		TI = 0;
		sendFlg = 1;
	}
} //obsluga przerwania portu transmisji szeregowej

void obslugaKlawiaturyMat(void)
{
	//obsluga jedynie strzalek w gore i dol
	if(kbd1 & 0b00100000) { //strzalka w gore (C)
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

	if(kbd1 & 0b00010000) { //strzalka w dol (D)
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
	//zobacz jaki przycisk trzeba obsluzyc
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
	if(kbdMux == 0b00001000) { // ^ (strzalka w gore)
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
	if(kbdMux == 0b00010000) { // V (strzalka w dol)
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
} //obsluga klawiszy klawiatury multipleksowanej

void refresh7Seg(void)
{
	//obsługa klawiatury matrycowej
	kbd1 = *CSKB1;
	if(kbd1 != kbdPoprz)
		obslugaKlawiaturyMat();
	kbdPoprz = *CSKB1;
	
	//refresh data7segietlaczy
	S7ON = 1; //wyłączam wyświetlacze
	*CSDS =  wybranyWys;
	*CSDB = znaki[data7seg[iter7Seg]];
	S7ON = 0; //włączam wyświetlacze

	//zapamietujemy stan dla klawiatury multipleksowanej
	kbdMuxPoprz = wybranyWys;

	//przygotowania pod kolejny obrót pętli
	iter7Seg++;
	wybranyWys = rotateLeft(wybranyWys);
	if(iter7Seg > 5) { //odświeżyliśmy wszystko
		iter7Seg = 0;
		wybranyWys = 0b00000001;
	}
} /* funkcja ta zajmuje się refreshowaniem data7segietlaczy, diód led
	 * oraz sprawdzaniem stanów klawiszy klawiatury matrycowej i multipleksowanej
	 */

unsigned char rotateLeft(unsigned char x)
{
	unsigned char tmp = x;
	x = (tmp << 1) | (tmp >> 7);
	return x;
} //funkcja ta przenosi bity x o jeden w lewo

unsigned char rotateRight(unsigned char x)
{
	unsigned char tmp = x;
	x = (tmp >> 1) | (tmp << 7);
	return x;
} //funkcja ta przenosi bity x o jeden w prawo
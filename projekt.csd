/* Program obsługujący układy czasowo-licznikT0interowe */
#include <8051.h>
//get chyba dziala -- set i edit sie niszczy czasem
//zrob lepsze rozpoznawanie komend!!!

// 7segment display select
__xdata unsigned char* CSDS = (__xdata unsigned char*) 0xFF30; 
// 7segment display buffer
__xdata unsigned char* CSDB = (__xdata unsigned char*) 0xFF38;
// klawiatura matrycowa klawisze od 8 do F 
__xdata unsigned char* CSKB1 = (__xdata unsigned char*) 0xFF22;
__sbit __at(0x96) S7ON; //bit przelączania wyświetlacza 7 sementowego
__sbit __at(0x97) TLED; //bit diody TEST
__sbit __at(0xB5) MUXK; //bit stan klawiatury MUX

//od 0 do 9 znaki zwykle od 0 do 9
//od 10 do 20 znaki z kropka od 0. do 9.
__code unsigned char znaki[26] = {0b00111111, 0b00000110, 0b01011011,
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
void wyczyscBuffery(void);
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
unsigned char sendBuff[8]; //bufor nadawania
unsigned char iRecvB; //iterator bufora odbierania
unsigned char iSendB; //iterator bufora nadawania
unsigned char i; //iterator
//zmienne do przechowywania komend
__xdata __at(0x5000) unsigned char cmdHist[10][13]; //historia komend zapisywana w zewnentrznej pamieci RAM
__xdata __at(0x4500) unsigned char cmdStat[10]; //status komend (0 - err; 1 - ok)
unsigned char curCmds;
//uzyte 48/80 bajtow (General prupose)
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
//uzyte 9/128 bitow (16-bit addressable register)

void main(void)
{
	seg7Init();
	timerSerialInit();
	while(1) {
		if(flagInterruptT0 == 1) { //chcemy odświeżać tylko gdy jest przerwanie
			flagInterruptT0 = 0;
			
			//zaktualizuj czas, wartosci dla wyswietlacza 7seg oraz odswiez 7seg
			updateTime();
			refreshTimeValuesFor7Seg();
			refresh7Seg();
		}

		if(recvFlg == 1) {
			recvFlg = 0;
			recvBuff[iRecvB] = SBUF; //odbierz znak
			if(recvBuff[iRecvB] == 10) { //znak LF
				if(recvBuff[iRecvB - 1] == 13) { //znak CR (w sumie mamy CR+LF
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
		if(sendFlg == 1) {
			sendFlg = 0;
			if(iSendB < 8) {
				SBUF = sendBuff[iSendB];
				iSendB++;
			}
		}
		//sprawdzmy teraz flagi komend
		//obsluga edit
		if(editFlg == 1) {
			editFlg = 0;
			if(editMode == 0) {
				editMode = 1;
				stareSekundy = sekundy;
				stareMinuty = minuty;
				stareGodziny = godziny;
			}
		}
		//obsluga get
		if(getFlg == 1) {
			getFlg = 0;
			obslugaGetCommand();
			iSendB = 0;
			//trzeba cos poprawic, get znaczaco opoznia zliczanie czasu
		}
		//obsluga set
		if(setFlg == 1) {
			setFlg = 0;
			obslugaSetCommand();
		}
		//obsluga blednych komend
		if(errorFlg == 1) {
			//tutaj trzeba zrobic error handling
			errorFlg = 0;
		}

	} //while
} //main

void recognizeCommand(void)
{
	if(recvBuff[0] == 'S' && recvBuff[1] == 'E' && recvBuff[2] == 'T' && recvBuff[3] == ' ' && recvBuff[6] == '.' && recvBuff[9] == '.' && recvBuff[12] == 13 && recvBuff[13] == 10)
		setFlg = 1;
	else if(recvBuff[0] == 'G' && recvBuff[1] == 'E' && recvBuff[2] == 'T' && recvBuff[3] == 13 && recvBuff[4] == 10)
		getFlg = 1;
	else if(recvBuff[0] == 'E' && recvBuff[1] == 'D' && recvBuff[2] == 'I' && recvBuff[3] == 'T' && recvBuff[4] == 13 && recvBuff[5] == 10)
		editFlg = 1;
	else if(recvBuff[0] == 's' && recvBuff[1] == 'e' && recvBuff[2] == 't' && recvBuff[3] == ' ' && recvBuff[6] == '.' && recvBuff[9] == '.' && recvBuff[12] == 13 && recvBuff[13] == 10)
		setFlg = 1;
	else if(recvBuff[0] == 'g' && recvBuff[1] == 'e' && recvBuff[2] == 't' && recvBuff[3] == 13 && recvBuff[4] == 10)
		getFlg = 1;
	else if(recvBuff[0] == 'e' && recvBuff[1] == 'd' && recvBuff[2] == 'i' && recvBuff[3] == 't' && recvBuff[4] == 13 && recvBuff[5] == 10)
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
	editMode = 1;
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
		errorFlg = 1;
		godziny = stareGodziny;
		minuty = stareMinuty;
		sekundy = stareSekundy;
	}
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

	//upewniamy sie ze iteratori i flagi sa wyzerowane
//	wyczyscBuffery();
	iRecvB = iSendB = i = 0;
	recvFlg = sendFlg = 0;
	RI = TI = 0;
	getFlg = setFlg = editFlg = errorFlg = editMode = 0;
} //inicjalizacja timerów (i ich przerwań) oraz portu szeregowego

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

void seg7Init(void)
{
	wybranyWys = 0b00000001;
	iter7Seg = 0;
	unsigned char i;
	for(i = 0; i < 6; i++)
		data7seg[i] = 0;
}

void obslugaKlawiaturyMat(void)
{
	//work in progress
	//obsluga jedynie strzalek w gore i dol
}

void obslugaKlawiaturyMux(void)
{
	if(kbdMux & 0b00000001) { // Enter (save changes)
		if(editMode == 1)
			editMode = 0;
	}
	if(kbdMux & 0b00000010) { //Esc (discard changes)
		if(editMode == 1) {
			sekundy = stareSekundy;
			minuty = stareMinuty;
			godziny = stareGodziny;
			editMode = 0;
		}
	}
	if(kbdMux & 0b00000100) { // ->
		if(editMode == 0) {
			editMode = 1;
			stareSekundy = sekundy;
			stareMinuty = minuty;
			stareGodziny = godziny;
		}
		if(selector == 0)
			selector = 2;
		else
			selector--;
	}
	if(kbdMux & 0b00100000) { // <-
		if(editMode == 0) {
			editMode = 1;
			stareSekundy = sekundy;
			stareMinuty = minuty;
			stareGodziny = godziny;
		}
		if(selector == 2)
			selector = 0;
		else
			selector++;
	}
	if(kbdMux & 0b00001000) { // ^ (strzalka w gore)
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
	if(kbdMux & 0b00010000) { // V (strzalka w dol)
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

	//obsługa klawiatury multipleksowanej
	if(MUXK == 1) {
		kbdMux = kbdMux | wybranyWys;
		if(kbdMux != kbdMuxPoprz) {
			obslugaKlawiaturyMux();
		}
	}

	//przygotowania pod kolejny obrót pętli
	iter7Seg++;
	wybranyWys = rotateLeft(wybranyWys);
	if(iter7Seg > 5) { //odświeżyliśmy wszystko
		iter7Seg = 0;
		wybranyWys = 0b00000001;
		kbdMuxPoprz = kbdMux; //zapamietaj stan klawiatury na nastepne przejscie
		kbdMux = 0; //po przecjsciu calego wyswietlacza resetuj stan klawiatury
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

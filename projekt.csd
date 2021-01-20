/* Program obsługujący układy czasowo-licznikT0interowe */
#include <8051.h>
//skonczone zadania 1,2,3 (w 3 postaraj sie zrobic zeby mozna bylo kilka
//klawiszy na raz wcisnac i usun cpl na tledzie z funkcji oblsugi klawiszy mux

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
void timerInit(void);
unsigned char rotateLeft(unsigned char x);
unsigned char rotateRight(unsigned char x);
void t0Interrupt(void) __interrupt(1);
void refreshTimeValuesFor7Seg(void);
void updateTime(void);
void obslugaKlawiaturyMat(void);
void obslugaKlawiaturyMux(void);
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
//flagi bitowe
__bit flagInterruptT0; //flaga przerwania
__bit flagSecondPassed; //flaga miniecia 1 sekundy
__bit editMode; //flaga trybu edycji


void main(void)
{
	seg7Init();
	timerInit();
	while(1) {
		if(flagInterruptT0 == 1) { //chcemy odświeżać tylko gdy jest przerwanie
			flagInterruptT0 = 0;
			
			updateTime();
			refreshTimeValuesFor7Seg();
			refresh7Seg();
		}
	}
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

//tutaj inicjujemy wszystko zwiazane z obsluga timera0 (zliczanie czasu)
void timerInit(void)
{
	TMOD = 0b01110001; //timer 1 wyłączony, timer 0 w trybie 16bitowym
	TR0 = 1; //uruchom timer 0
	ET0 = 1; //zezwól na przerwania od timera 0
	EA = 1; //zezwól na przerwania ogólnie
	TH0 = 252; //chcemy przepełniać TH0 4 razy -- da to 900 przepełnień na sekundę
	TL0 = 0; //TL0 ma być na 0
	licznikT0inter = 0; //licznikT0inter zlicza do 900 i jest inicjalizowany zerem
	sekundy = 0;
	minuty = 0;
	godziny = 0;
	flagInterruptT0 = flagSecondPassed = editMode = 0;
	selector = 0;
} //inicjalizacja timerów (i ich przerwań)

void t0Interrupt(void) __interrupt(1)
{
	TH0 = 252; //przeładuj TH0
	flagInterruptT0 = 1; //zasygnalizuj przerwanie
	if(editMode == 0)
		licznikT0inter++;
	if(licznikT0inter == 900) {
		flagSecondPassed = 1;
	}
} //obsługa przerwania timera 0

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
		TLED = 1 - TLED;
		if(editMode == 1)
			editMode = 0;
	}
	else if(kbdMux & 0b00000010) { //Esc (discard changes)
		TLED = 1 - TLED;
		if(editMode == 1) {
			sekundy = stareSekundy;
			minuty = stareMinuty;
			godziny = stareGodziny;
			editMode = 0;
		}
	}
	else if(kbdMux & 0b00000100) { // ->
		TLED = 1 - TLED;
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
	else if(kbdMux & 0b00100000) { // <-
		TLED = 1 - TLED;
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
	else if(kbdMux & 0b00001000) { // ^ (strzalka w gore)
		TLED = 1 - TLED;
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
	else if(kbdMux & 0b00010000) { // V (strzalka w dol)
		TLED = 1 - TLED;
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

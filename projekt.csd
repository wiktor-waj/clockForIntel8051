/* Program obsługujący układy czasowo-licznikT0interowe */
#include <8051.h>

// 7segment display select
__xdata unsigned char* CSDS = (__xdata unsigned char*) 0xFF30; 
// 7segment display buffer
__xdata unsigned char* CSDB = (__xdata unsigned char*) 0xFF38;
// klawiatura matrycowa klawisze od 8 do F 
__xdata unsigned char* CSKB1 = (__xdata unsigned char*) 0xFF22;
__sbit __at(0x96) S7ON; //bit przelączania wyświetlacza 7 sementowego
__sbit __at(0x97) TLED; //bit diody TEST
__sbit __at(0xB5) MUXK; //bit stan klawiatury MUX

//znaki od 0 do F dla wyswietlacza 7 seg
__code unsigned char znaki[16] = {0b00111111, 0b00000110, 0b01011011,
																 	0b01001111, 0b01100110, 0b01101101, 
																	0b01111101, 0b00000111, 0b01111111, 
																	0b01101111, 0b01110111, 0b00111100,
																	0b10111001, 0b01011110, 0b01111001, 
																	0b01110001};

//etykiety funkcji
void refresh7Seg(void);
void seg7Init(void);
void timerInit(void);
unsigned char rotateLeft(unsigned char x);
unsigned char rotateRight(unsigned char x);
void t0Interrupt(void) __interrupt(1);
void refreshTimeValuesFor7Seg(void);
void updateTime(void);
//zmienne
unsigned char wybw; //wybrany wyswietlacz bitowo
unsigned char iter7Seg; //index do iteracji po wyswietlaczach
unsigned char wysw[6]; //tabela przechowująca dane do wyświetlania na wyś. 7seg.
int licznikT0inter; //licznik przerwań ukladu T0 -- powinień liczyć do 900
unsigned char sekundy; //liczba sekund, które upłynęły
unsigned char minuty; //liczba minut, ktore uplynely
unsigned char godziny; //liczba godzin, ktore uplynely
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
		P1_7 = 1 - P1_7;
	}
} //funkcja zajmuje sie aktualizacja wartosci czasu

void refreshTimeValuesFor7Seg(void)
{
	if(iter7Seg == 0) //odswiezamy jednosci sekund
		wysw[0] = sekundy % 10;
	else if(iter7Seg == 1) //odswiezamy dziesiatki sekund
		wysw[1] = (unsigned char)(sekundy / 10);
	else if(iter7Seg == 2)  //odswiezamy jednosci minut
		wysw[2] = minuty % 10;
	else if(iter7Seg == 3) //odswiezamy dziesiatki minut
		wysw[3] = (unsigned char)(minuty / 10);
	else if(iter7Seg == 4) //odswiezamy jednosci godzin
		wysw[4] = godziny % 10;
	else if(iter7Seg == 5) //odswiezamy dziesiatki godzin
		wysw[5] = (unsigned char)(godziny / 10);
} //funkcja ta zajmuje sie odswiezaniem wartosci dla wyswietlaczy 7seg

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
} //inicjalizacja timerów (i ich przerwań)

void t0Interrupt(void) __interrupt(1)
{
	TH0 = 252; //przeładuj TH0
	flagInterruptT0 = 1; //zasygnalizuj przerwanie
	licznikT0inter++;
	if(licznikT0inter == 900) {
		flagSecondPassed = 1;
	}
} //obsługa przerwania timera 0

void seg7Init(void)
{
	wybw = 0b00000001;
	iter7Seg = 0;
	unsigned char i;
	for(i = 0; i < 6; i++)
		wysw[i] = 0;
	P1_7 = 1;
}

void refresh7Seg(void)
{

	//refresh wyswietlaczy i ledów
	S7ON = 1; //wyłączam wyświetlacze
	*CSDS =  wybw;
	*CSDB = znaki[wysw[iter7Seg]];
	S7ON = 0; //włączam wyświetlacze

	//przygotowania pod kolejny obrót pętli
	iter7Seg++;
	wybw = rotateLeft(wybw);
	if(iter7Seg > 5) { //odświeżyliśmy wszystko
		iter7Seg = 0;
		wybw = 0b00000001;
	}
} /* funkcja ta zajmuje się refreshowaniem wyswietlaczy, diód led
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

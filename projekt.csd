/* Program obsługujący układy czasowo-licznikowe */
#include <8051.h>

/* 7segment display select */
__xdata unsigned char* CSDS = (__xdata unsigned char*) 0xFF30; 
/* 7segment display buffer */
__xdata unsigned char* CSDB = (__xdata unsigned char*) 0xFF38;
__sbit __at(0x96) S7ON; //bit przelączania wyświetlacza 7 sementowego
__bit flagaPrzer; //flaga przerwania

//znaki od 0 do F dla wyswietlacza 7 seg
__code unsigned char znaki[16] = {0b00111111, 0b00000110, 0b01011011,
																 	0b01001111, 0b01100110, 0b01101101, 
																	0b01111101, 0b00000111, 0b01111111, 
																	0b01101111, 0b01110111, 0b00111100,
																	0b10111001, 0b01011110, 0b01111001, 
																	0b01110001};

void _7SEG_REFRESH(void);
void _7SEG_INIT(void);
void timerInit(void);
unsigned char rotateLeft(unsigned char x);
unsigned char rotateRight(unsigned char x);
void t0_int(void) __interrupt(1);
void odswiezWartosci(void);
unsigned char wybw; //wybrany wyswietlacz bitowo
unsigned char wybi; //index do iteracji po wyswietlaczach
unsigned char wysw[6]; //tabela przechowująca dane do wyświetlania na wyś. 7seg.
int licznik; //licznik przerwań -- powinień liczyć do 900
unsigned char sekundy; //liczba sekund, które upłynęły


void main(void)
{
	_7SEG_INIT();
	timerInit();
	while(1) {
		if(flagaPrzer == 1) { //chcemy odświeżać tylko gdy jest przerwanie
			flagaPrzer = 0;
			if(licznik == 900) { //odmieżono sekunde
				licznik -= 900;
				sekundy++;
				P1_7 = 1 - P1_7;

			}
			odswiezWartosci();
			_7SEG_REFRESH();
		}
	}
}

void odswiezWartosci(void)
{
	if(wybi == 0) //odswiezamy jednosci licznika
		wysw[0] = licznik % 10;
	else if(wybi == 1) //odswiezamy dziesiatki licznika
		wysw[1] = (licznik / 10) % 10;
	else if(wybi == 2)  //odswiezamy setki licznika
		wysw[2] = (licznik / 100) % 10;
	else if(wybi == 3) //odswiezamy jednosci sekund
		wysw[3] = sekundy % 10;
	else if(wybi == 4) //odswiezamy dziesiatki sekund
		wysw[4] = (sekundy / 10) % 10;
	else if(wybi == 5) //odswiezamy setki sekund
		wysw[5] = (sekundy / 100) % 10;
} //funkcja ta zajmuje sie odswiezaniem wartosci dla wyswietlaczy 7seg

void timerInit(void)
{
	TMOD = 0b01110001; //timer 1 wyłączony, timer 0 w trybie 16bitowym
	TR0 = 1; //uruchom timer 0
	ET0 = 1; //zezwól na przerwania od timera 0
	EA = 1; //zezwól na przerwania ogólnie
	TH0 = 252; //chcemy przepełniać TH0 4 razy -- da to 900 przepełnień na sekundę
	TL0 = 0; //TL0 ma być na 0
	licznik = 0; //licznik zlicza do 900 i jest inicjalizowany zerem
	sekundy = 0; //zliczanie sekund
} //inicjalizacja timerów (i ich przerwań)

void t0_int(void) __interrupt(1)
{
	TH0 = 252; //przeładuj TH0
	flagaPrzer = 1; //zasygnalizuj przerwanie
	licznik++;
} //obsługa przerwania timera 0

void _7SEG_INIT(void)
{
	wybw = 0b00000001;
	wybi = 0;
	unsigned char i;
	for(i = 0; i < 6; i++)
		wysw[i] = 0;
	P1_7 = 1;
}

void _7SEG_REFRESH(void)
{

	//refresh wyswietlaczy i ledów
	S7ON = 1; //wyłączam wyświetlacze
	*CSDS =  wybw;
	*CSDB = znaki[wysw[wybi]];
	S7ON = 0; //włączam wyświetlacze

	//przygotowania pod kolejny obrót pętli
	wybi++;
	wybw = rotateLeft(wybw);
	if(wybi > 5) { //odświeżyliśmy wszystko
		wybi = 0;
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

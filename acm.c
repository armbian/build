#define HSLEEP 11
#define TESTFILE "/tmp/acm.testfile.47"
#define AFFCPU "/sys/devices/system/cpu/cpufreq/policy0/affected_cpus"
#define CPUI "/proc/cpuinfo"
#define VER "/proc/version"
#define HN "/etc/hostname"
#define MINFQ "/sys/devices/system/cpu/cpufreq/policy0/scaling_min_freq"
#define MAXFQ "/sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq"
#define GOV "/sys/devices/system/cpu/cpufreq/policy0/scaling_governor"
#define FREQ "/sys/devices/system/cpu/cpufreq/policy0/cpuinfo_cur_freq"
#define SOCT "/etc/armbianmonitor/datasources/soctemp"
#define LDAVG "/proc/loadavg"
#define PSTAT "/proc/stat"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <math.h>
#include <sys/select.h>
#include <sys/time.h>
#include <sys/types.h>
#include <unistd.h>

FILE *fp;
size_t yards=247;
size_t yardsgained;
char *linebacker, *uname, *freqgov;
char cpus[19], version[47], model[2][255];
int cpustat[8], cpustat0[8], deltaStat[8], freqcpus[8];
int scroll, secs, rcnt, x, i, minfreq, maxfreq, freq, temp, corecnt = 0;
float cnt, ctemp, ftemp, decsecs, iLoad, cLoad, tcLoad, uLoad, nLoad, sLoad, wLoad, qLoad, rLoad, irqLoad, acLoad = 0;
float loadavg[3];
long stat_sec, selstart_usec = 0;

struct timeval sel_tv;

void zeroCounters(void);
void print_stats(void);
void print_app_usage(void);
void print_header(void);
void print_help(void);

int main(int argc, char **argv)
{
	for (i=0;i<7;i++) {
		cpustat[i] = cpustat0[i] = deltaStat[i] = 0;
	}
	deltaStat[7] = 0;
	while ((++argv)[0]) {
		if (argv[0][0] == '-' ) {
			switch (argv[0][1])  {
				default:
					printf("Unknown option -%c\n\n", argv[0][1]);
					print_app_usage();
					exit(EXIT_FAILURE);
					break;
				case 'h':
					print_app_usage();
					exit(EXIT_FAILURE);
					break;
				case 's':
					if ((argv[1]) != NULL) {
						scroll = atoi(argv[1]);
					}
					break;
				case 't':
					if ((argv[1]) != NULL) {
						secs = atoi(argv[1]);
						decsecs = fmod(atof(argv[1]), 1);
					}
					break;
			}
		}
	}
	if (secs+decsecs == 0) {
		decsecs = 0.1;
	}
	struct timespec pseudoSleep = {0};
		pseudoSleep.tv_sec = secs;
		pseudoSleep.tv_nsec = decsecs * 1000000000L;
	if( access(AFFCPU, F_OK ) != -1 ) {
		fp = fopen(AFFCPU, "r");
			if (fp != NULL){
				  linebacker = (char *) malloc (yards + 1);
				  yardsgained = getline (&linebacker, &yards, fp);
				  corecnt = yardsgained/2;
				  freqcpus[0] = atoi((strtok(linebacker," ")));
				  for (i=1;i<corecnt;i++) {
					  freqcpus[i] = atoi((strtok(NULL," ")));
				  }
			}
		fclose(fp);
	}
	if( access(CPUI, F_OK ) != -1 ) {
		fp = fopen(CPUI, "r");
		if (fp != NULL){
			linebacker = (char *) malloc (yards + 1);
			while (yardsgained = getline (&linebacker, &yards, fp) != -1) {
				sprintf(model[0], "%s", (strtok(linebacker, ":")));
				sprintf(model[1], "%s", (strtok(NULL, ":")));
				if (strcmp(model[0], "model name\t") == 0) {
					break;
				}
			}
		}
		fclose(fp);
	}
	if( access(VER, F_OK ) != -1 ) {
		fp = fopen(VER, "r");
			if (fp != NULL){
				linebacker = (char *) malloc (yards + 1);
				yardsgained = getline (&linebacker, &yards, fp);
				sprintf(version, "%s", (strtok(linebacker, " ")));
				for (i=0;i<2;i++) {
					sprintf(version, "%s", (strtok(NULL, " ")));
				}
			 }
		fclose(fp);
	}
	if( access(HN, F_OK ) != -1 ) {
		fp = fopen(HN, "r");
			if (fp != NULL){
				uname = (char *) malloc (yards + 1);
				yardsgained = getline (&uname, &yards, fp);
			}
		fclose(fp);
	}

	if( access(MINFQ, F_OK ) != -1 ) {
		fp = fopen(MINFQ, "r");
			if (fp != NULL){
				linebacker = (char *) malloc (yards + 1);
				yardsgained = getline (&linebacker, &yards, fp);
				minfreq = atoi(linebacker);
			}
		fclose(fp);
	}
	if( access(MAXFQ, F_OK ) != -1 ) {
		fp = fopen(MAXFQ, "r");
			if (fp != NULL){
				linebacker = (char *) malloc (yards + 1);
				yardsgained = getline (&linebacker, &yards, fp);
				maxfreq = atoi(linebacker);
			}
		fclose(fp);
	}
	if( access(GOV, F_OK ) != -1 ) {
		fp = fopen(GOV, "r");
			if (fp != NULL){
				freqgov = (char *) malloc (yards + 1);
				yardsgained = getline (&freqgov, &yards, fp);
			}
		fclose(fp);
	}
	print_help();
	while (1) {
		if( access(FREQ, F_OK ) != -1 ) {
			fp = fopen(FREQ, "r");
				if (fp != NULL){
					linebacker = (char *) malloc (yards + 1);
					yardsgained = getline (&linebacker, &yards, fp);
					freq = atoi(linebacker);
				}
			fclose(fp);
		}
		if( access(SOCT, F_OK ) != -1 ) {
			fp = fopen(SOCT, "r");
				if (fp != NULL){
					linebacker = (char *) malloc (yards + 1);
					yardsgained = getline (&linebacker, &yards, fp);
					temp = atoi(linebacker);
				}
			fclose(fp);
		}
		ctemp = (float)temp/1000;
		ftemp = ctemp*9/5+32;
		if( access(LDAVG, F_OK ) != -1 ) {
			fp = fopen(LDAVG, "r");
				if (fp != NULL){
					linebacker = (char *) malloc (yards + 1);
					yardsgained = getline (&linebacker, &yards, fp);
					loadavg[0] = atof((strtok(linebacker," ")));
					for (i=1;i<3;i++) {
						loadavg[i] = atof((strtok(NULL," ")));
					}
				}
			fclose(fp);
		}
		if( access(PSTAT, F_OK ) != -1 ) {
			fp = fopen(PSTAT, "r");
				if (fp != NULL){
					linebacker = (char *) malloc (yards + 1);
					yardsgained = getline (&linebacker, &yards, fp);
					char *oob = (strtok(linebacker," "));
					for (i=0;i<7;i++) {
						cpustat[i] = atoi((strtok(NULL," ")));
					}
				}
			fclose(fp);
		}
		deltaStat[7] = 0;
		for (i=0; i<7; i++) {
			deltaStat[i] = cpustat[i] - cpustat0[i];
			deltaStat[7] += deltaStat[i];
		}
		freq /= 1000;
		if (rcnt != 0) {
			if (scroll == 0) {
				printf ("\x1b[1A");
			}
			if ( deltaStat[7] != 0 ) {
				cLoad = (float)(deltaStat[7] - (float)deltaStat[3])/(float)deltaStat[7];
				tcLoad += cLoad;
				acLoad = tcLoad/(float)rcnt;
				uLoad = (float)deltaStat[0]/(float)deltaStat[7];
				nLoad = (float)deltaStat[1]/(float)deltaStat[7];
				sLoad = (float)deltaStat[2]/(float)deltaStat[7];
				iLoad = (float)deltaStat[3]/(float)deltaStat[7];
				wLoad = (float)deltaStat[4]/(float)deltaStat[7];
				qLoad = (float)deltaStat[5]/(float)deltaStat[7];
				rLoad = (float)deltaStat[6]/(float)deltaStat[7];
				irqLoad = (float)((qLoad + rLoad)/(float)deltaStat[7]);
			}
			print_stats();
		}
		rcnt++;
		for (i=0; i<7; i++) {
			cpustat0[i] = cpustat[i];
		}
		char que[255] = {};
		fd_set readfds;
		int fd_stdin;
		fd_stdin = fileno(stdin);
		FD_ZERO(&readfds);
		FD_SET(fileno(stdin), &readfds);
		fflush(stdin);
		fflush(stdout);
		gettimeofday (&sel_tv, NULL);
		selstart_usec = sel_tv.tv_sec * 1000000 + sel_tv.tv_usec;
		int sret = pselect(fd_stdin + 1, &readfds, NULL, NULL, &pseudoSleep, NULL);
		if ( sret > 0 ) {
			fgets(que, 255, stdin);
			if (scroll == 47) {
				 printf("\neffingGot: %d\n", que[0]);
			}
			if ( que[0] == 10  && scroll != 0 ) {
				print_header();
			} else if ( que[0] == 47 ) {
				scroll = (scroll==0)?(1):(0);
				if (scroll == 0) print_header();
			} else if ( que[0] == 113 || que[0] == 81 ) {
				exit(0);
			} else if ( que[0] == 122 || que[0] == 90 ) {
				x=9;
			} else if (( que[0] == 104 || que[0] == 72 ) && scroll != 0 ) {
				print_help();
			}
		}
		if ( x == 9 ) {
			printf ("\x1b[1A");
			zeroCounters();
			x=0;
		} else {
			gettimeofday (&sel_tv, NULL);
			cnt += (float)(((sel_tv.tv_sec * 1000000 + sel_tv.tv_usec) - selstart_usec)*0.000001);
		}
	}
}
void
zeroCounters(void)
{
	for (i=0;i<8;i++) {
		cpustat[i] = deltaStat[i] = 0;
	}
	tcLoad=0;
	rcnt=0;
	cnt=0;
}
void
print_stats()
{
	struct timeval tv;
	struct tm* myty;
	char ty_string[40];

	gettimeofday (&tv, NULL);
	stat_sec = tv.tv_sec;
	myty = localtime (&stat_sec);
	strftime (ty_string, sizeof (ty_string), "%H:%M:%S", myty);
	printf ("%-9.2f %8s       %-4iMHz       %-5.1f %-5.1f    %-4.2f %-4.2f %-4.2f    %-9.2f%-9.2f%-9.2f%-9.2f%-9.2f%-9.2f%-9.2f%-9.2f\n", cnt,ty_string,freq,ctemp,ftemp,loadavg[0],loadavg[1],loadavg[2],iLoad,cLoad,acLoad,sLoad,uLoad,nLoad,wLoad,irqLoad);
}
void
print_help()
{
	printf ("\ncpu statistics monitor_______________________________________________________________________________________________________________________\n\n");
	printf ("  hostname: %s\n", uname);
	printf ("  linux version: %s\n", version);
	printf ("  cpu model: %s\n", model[1]);
	printf ("\x1b[1A  freq.union.cores: ");
	for (i=0; i<corecnt; i++)  {
		printf ("%i ", freqcpus[i]);
	}
	printf ("\n   | min.freq: %-7i\n   | max.freq: %-7i\n   | freq.gov: %9s\n\n", minfreq, maxfreq, freqgov);
	if ( scroll > 0 ) {
		printf ("  [<ENTER>: reprint column headings]\n");
		printf ("  ['h'+<ENTER>: display help]\n");
	}
	printf ("  ['/'+<ENTER>: flip display mode (fixed-line/scrolling)]\n");
	printf ("  ['z'+<ENTER>: reset all counters]\n");
	printf ("  ['q'+<ENTER> || <CTRL-c>: exit cpu statistics monitor\n");
	printf ("\n  display interval:  %-4.3f\n\n", secs+decsecs);
	if ( cnt != 0 ) {
		struct timespec helpSleep = {0};
			helpSleep.tv_sec = 1;
			helpSleep.tv_nsec = 0 * 1000000000L;
		for (i=HSLEEP; i>0; i--) {
			nanosleep(&helpSleep, (struct timespec *)NULL);
			printf("resuming cpu statistics monitor in....%is\n", i-1);
			printf ("\x1b[1A");
		}
		printf ("\x1b[1A");
		print_header();
	} else {
		print_header();
	}
}
void
print_app_usage(void)
{
	printf("\n");
	printf("Options: -h -d -t\n");
	printf("-h: help \n");
	printf("-d device \n");
	printf("-t display interval [format s.x (e.g. 1.0] \n");
	printf("\n");
}
void
print_header(void)
{
	printf ("\n___________________  %-124s\n", "|cpu.stats_____________________________________________________________________________________________________________");
	printf ("                     %-1s\n", "|");
	printf ("                     %-1s   ", "|");
	printf ("%-16s%-14s%-12s\n","core.freq","cpu.temp","load.average");
	printf ("%-10s %-8s   |   ", "\u01A9.int","time");
	printf ("% i - %i", freqcpus[0], freqcpus[corecnt-1]);
	printf ("          %-4s|%-6s    %-4s %-4s %-4s    %-9s%-9s%-11s%-8s%-9s%-9s%-9s%-9s\n\n","\u00B0C","\u00B0F","1m","5m","15m","idle","cpu ","\u01B0cpu","sys ","user","nice","ioio","irqs");
	if (scroll == 0) {
		printf ("\n");
	}
}

#define HSLEEP 11
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <math.h>
#include <sys/select.h>
#include <sys/time.h>
#include <sys/types.h>
#include <unistd.h>
#include <errno.h>

FILE *fp;
char stuffed[255];
char uname[255];
char *dev = NULL;
char *scr = NULL;
char str1[10], freqgov[19], minfreq[9], maxfreq[9], cpu[18], version[40], model[2][255];
int procss, lastproc, secs, rcnt, scroll, x, i, l, ret, freq, temp = 0;
int interval[2], cpustat[7], cpustat0[7], deltaStat[8], freqcpus[8];
float cnt, ctemp, ftemp, decsecs, loadavg, loadavg5, loadavg15, cLoad, tcLoad, uLoad, nLoad, sLoad, wLoad, qLoad, rLoad, irqLoad, dtxid, acLoad = 0;
long stat_sec, selstart_usec = 0;
float seldiff_usec = 0;

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
					scroll = atoi(argv[1]);
					break;
				case 't':
					secs = atoi(argv[1]);
					decsecs = fmod(atof(argv[1]), 1); 
					break;
			}
		}
	}
	struct timespec pseudoSleep = {0};
		pseudoSleep.tv_sec = secs;
		pseudoSleep.tv_nsec = decsecs * 1000000000L;
	fp = fopen("/sys/devices/system/cpu/cpufreq/policy0/affected_cpus", "r");
		l=0;
		while (fscanf(fp, "%s", cpu) == 1) {
			freqcpus[l] = atoi(strtok(cpu, " "));
			l++;
		}
	fclose(fp);
	fp = fopen("/proc/cpuinfo", "r");
		while (fgets(stuffed, 255, fp) != NULL)  {
			sprintf(model[0], "%s", (strtok(stuffed, ":")));
			sprintf(model[1], "%s", (strtok(NULL, ":")));
			if (strcmp(model[0], "model name\t") == 0) {
				break;
			}
		}
	fclose(fp);
	fp = fopen("/proc/version", "r");
		for (i=0;i<3;i++) {
			fscanf(fp, "%s", stuffed);
			sprintf(version, "%s", (strtok(stuffed, " ")));
		}
	fclose(fp);
	fp = fopen("/etc/hostname", "r");
		fscanf(fp, "%s", uname);
	fclose(fp);
	fp = fopen("/sys/devices/system/cpu/cpufreq/policy0/scaling_min_freq", "r");
		(fgets(minfreq, 9, (FILE*)fp));
	fclose(fp);
	fp = fopen("/sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq", "r");
		(fgets(maxfreq, 9, (FILE*)fp));
	fclose(fp);
	fp = fopen("/sys/devices/system/cpu/cpufreq/policy0/scaling_governor", "r");
		(fgets(freqgov, 19, (FILE*)fp));
	fclose(fp);
	print_help();
	while (1) {   
		fp = fopen("/sys/devices/system/cpu/cpufreq/policy0/cpuinfo_cur_freq", "r");
			freq = atoi(fgets(stuffed, 255, (FILE*)fp));
		fclose(fp);
		fp = fopen("/etc/armbianmonitor/datasources/soctemp", "r");
			temp = atoi(fgets(stuffed, 255, (FILE*)fp));
			fclose(fp);
			ctemp = (float)temp/1000;
			ftemp = ctemp*9/5+32;
		fp = fopen("/proc/loadavg", "r");
			fscanf(fp, "%f %f %f", &loadavg, &loadavg5, &loadavg15);
		fclose(fp);
		fp = fopen("/proc/stat", "r");
			ret = fscanf(fp, "%s %i %i %i %i %i %i %i", str1, &cpustat[0], &cpustat[1], &cpustat[2], &cpustat[3], &cpustat[4], &cpustat[5], &cpustat[6]); 
		fclose(fp);
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
//			cpustat[7] -= cpustat0[7];
			if ( deltaStat[7] != 0 ) {
				cLoad = (float)(deltaStat[7] - deltaStat[3])/deltaStat[7];
				tcLoad += cLoad;
				acLoad = tcLoad/rcnt;
				uLoad = (float)deltaStat[0]/(float)deltaStat[7];
				nLoad = (float)deltaStat[1]/(float)deltaStat[7];
				sLoad = (float)deltaStat[2]/(float)deltaStat[7];
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
		char que[1] = {};
		fd_set readfds;
		int fd_stdin;
		fd_stdin = fileno(stdin);
		FD_ZERO(&readfds);
		FD_SET(fileno(stdin), &readfds);
		fflush(stdout);
		fflush(stdin);
		gettimeofday (&sel_tv, NULL);
		selstart_usec = sel_tv.tv_sec * 1000000 + sel_tv.tv_usec;
		int sret = pselect(fd_stdin + 1, &readfds, NULL, NULL, &pseudoSleep, NULL);
		if ( sret > 0 ) {
			fgets(que, 3, stdin); // && 	printf("\b");
			if (scroll == 47) {
				 printf("\neffingGot: %d\n", que[0]);
			}
			if (( que[0] == 47 || que[0] == 32 ) && scroll != 0 ) { 
				print_header();
			} else if ( que[0] == 113 || que[0] == 81 ) {
				exit(0);
			} else if ( que[0] == 122 || que[0] == 90 ) {
				x=1;
			} else if (( que[0] == 104 || que[0] == 72 ) && scroll != 0 ) {
				print_help();
			}
		}
		if ( x == 1 ) { 
			printf ("\x1b[1A");
			zeroCounters();
			x=0;
		} else {
			gettimeofday (&sel_tv, NULL);
			seldiff_usec = ((sel_tv.tv_sec * 1000000 + sel_tv.tv_usec) - selstart_usec)*0.000001;
			cnt += seldiff_usec;
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
	printf ("%-9.2f %8s       %-4iMHz       %-5.1f %-5.1f    %-4.2f %-4.2f %-4.2f    %-9.2f%-9.2f%-9.2f%-9.2f%-9.2f%-9.2f%-9.2f\n", cnt,ty_string,freq,ctemp,ftemp,loadavg,loadavg5,loadavg15,cLoad,acLoad,sLoad,uLoad,nLoad,wLoad,irqLoad);
}
void
print_help()
{
	printf ("\ncpu statistics monitor___________________________________\n\n");
	if ( scroll > 0 ) {
		printf ("[<'h'|'H'+ENTER>: display help]\n");
		printf ("[<'/'|' '+ENTER>: reprint column headings]\n");
	}
	printf ("[<'z'|'Z'+ENTER>: reset all counters]\n");
	printf ("[<'q'|'Q'+ENTER> || CTRL-c>: exit cpu statistics monitor\n\n");
//	printf ("[\u01B0: average, \u01A9: sum]\n");
	printf ("hostname: %s\n", uname);
	printf ("linux version: %s\n", version);
	printf ("cpu model: %s\n", model[1]);
	printf ("affected.cpus: ");
	for (i=0; i<l; i++)  {
		printf ("%i ", freqcpus[i]);
	}
	printf ("\n | min.freq:  %-7s | max.freq: %-7s | freq.gov: %9s\n", minfreq, maxfreq, freqgov);
	printf ("\ndisplay interval:  %-4.3f\n\n", secs+decsecs);
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
	printf ("\n___________________  %-115s\n", "|cpu.stats______________________________________________________________________________________________________");
	printf ("                     %-1s\n", "|");
	printf ("                     %-1s   ", "|");
	for (i=0; i<l/2; i++) {
		printf (" ");
	}
	printf ("cpus");
	for (i=0; i<l/2; i++) {
		printf (" ");
	}
	for (i=0; i<8-l; i++) {
		printf ("  ");
	}
	printf("cpu.temp  ");
	printf("    load.average\n");
	printf ("%-10s %-8s   |   ", "\u01A9.int","time");
	for (i=0; i<l; i++) {
		printf ("%i ", freqcpus[i]);
	}
	for (i=0; i<8-l; i++) {
		printf ("  ");
	}
	printf ("%-4s|%-6s    %-4s %-4s %-4s    %-9s%-11s%-8s%-9s%-9s%-9s%-9s\n\n","\u00B0C","\u00B0F","1m","5m","15m","cpu","\u01B0.cpu","sys","user","nice","io","irq");
	if (scroll == 0) {
		printf ("\n");
	}
}

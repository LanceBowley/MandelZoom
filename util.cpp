#include <stdio.h>
#include <string.h>
#include <stdlib.h>

// pulled from http://stackoverflow.com/questions/2654480/writing-bmp-image-in-pure-c-c-without-other-libraries
void writeImg(unsigned char* imgArray, int nCols, int nRows, char* imagePath)
{
	char bmpFilePath[1000];
	strcpy(bmpFilePath, imagePath);
	strcat(bmpFilePath, ".bmp");

	char jpgFilePath[1000];
	strcpy(jpgFilePath, imagePath);
	strcat(jpgFilePath, ".jpg");

	FILE *f;
	int filesize = 54 + 3*nCols*nRows;  //w is your image width, h is image height, both int

	unsigned char bmpfileheader[14] = {'B','M', 0,0,0,0, 0,0, 0,0, 54,0,0,0};
	unsigned char bmpinfoheader[40] = {40,0,0,0, 0,0,0,0, 0,0,0,0, 1,0, 24,0};
	unsigned char bmppad[3] = {0,0,0};

	bmpfileheader[ 2] = (unsigned char)(filesize    );
	bmpfileheader[ 3] = (unsigned char)(filesize>> 8);
	bmpfileheader[ 4] = (unsigned char)(filesize>>16);
	bmpfileheader[ 5] = (unsigned char)(filesize>>24);

	bmpinfoheader[ 4] = (unsigned char)(       nCols    );
	bmpinfoheader[ 5] = (unsigned char)(       nCols>> 8);
	bmpinfoheader[ 6] = (unsigned char)(       nCols>>16);
	bmpinfoheader[ 7] = (unsigned char)(       nCols>>24);
	bmpinfoheader[ 8] = (unsigned char)(       nRows    );
	bmpinfoheader[ 9] = (unsigned char)(       nRows>> 8);
	bmpinfoheader[10] = (unsigned char)(       nRows>>16);
	bmpinfoheader[11] = (unsigned char)(       nRows>>24);

	f = fopen(bmpFilePath,"wb");
	fwrite(bmpfileheader,1,14,f);
	fwrite(bmpinfoheader,1,40,f);
	for(int i = 0; i < nRows; i++)
	{
	    fwrite(imgArray+(nCols*(nRows-i-1)*3),3,nCols,f);
	    fwrite(bmppad,1,(4-(nCols*3)%4)%4,f);
	}
	fclose(f);
	printf("Wrote image as bitmap\n");

	char systemCommand[1000];
	strcpy(systemCommand, "convert ");
	strcat(systemCommand, bmpFilePath);
	strcat(systemCommand, " ");
	strcat(systemCommand, jpgFilePath);
	system(systemCommand);
	printf("Converted bitmap to jpg\n");
}

#include <stdio.h>
#include <stdlib.h>
#include <cuda.h>
#include <cuda_runtime.h>
#include <string.h>

void render(unsigned char*, double x0, double y0, double xD, double yD, int nCols, int nRows, int limitIter);
void writeImg(unsigned char* imgArray, int nCols, int nRows, char* outputPath);

int main(int argc, char **argv)
{
        // Inputs
        int nCols = 10000;
        int nRows = 10000;
        double mag = 10; // 1
        double xC = -0.51; // -0.5
        double yC = 0.61;
        int limitIter = 600;

        // Determine grid properties
        double xL = 1.0 / mag;
        double yL = ((double) nRows / (double) nCols) * xL;
        double xD = xL / ((float) nCols);
        double yD = yL / ((double) nRows);
        double x0 = xC - 0.5 * (xL - xD);
        double y0 = yC + 0.5 * (yL - yD);

        unsigned char* imgArray = (unsigned char*) malloc(3 * nCols * nRows * sizeof(unsigned char));
        render(imgArray, x0, y0, xD, yD, nCols, nRows, limitIter);

        char imagePath[100];
        strcpy(imagePath, "/home/ubuntu/img");
        writeImg(imgArray, nCols, nRows, imagePath);
}

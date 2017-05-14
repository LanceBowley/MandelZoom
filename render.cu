#include <stdio.h>
#include <stdlib.h>
#include <cuda.h>
#include <cuda_runtime.h>
#include <thrust/sort.h>

__global__ void getIterationCounts(double x0, double y0, double xD, double yD, int nCols, int nRows, int limitIter, int* iterations)
{
	int x = threadIdx.x + blockIdx.x * blockDim.x;
	int y = threadIdx.y + blockIdx.y * blockDim.y;
	if (x >= nCols || y >= nRows) {return;}; // banish bad threads

	double zxOld = 0;
	double zyOld = 0;
	double zxNew = 0;
	double zyNew = 0;

	double cx = x0 + ((double) x) * xD;
	double cy = y0 - ((double) y) * yD;

	int escIter = -1; // Will vary from 0 (immediately outside the escape radius) to maxIter - 1; unless it never escapes, then it is -1

	for (int i = 0; i < limitIter; i++) {
		zxNew = ((zxOld * zxOld) - (zyOld * zyOld) + cx);
		zyNew = ((2 * zxOld * zyOld) + cy);
		if ((zxNew * zxNew + zyNew * zyNew) > 4) {escIter = i; break;}; // escape radius is 2. Therefore the square of the escape is 4
		zxOld = zxNew;
		zyOld = zyNew;
	}

	iterations[x + y * nCols] = escIter;
}

template<class T>
__global__ void getBlockwiseExtrema(const T* inputArray, T* blockwiseExtrema, int inputLength, int numBlocks, bool min)
{
    extern __shared__ float blockInput[];

    int globalIdx = threadIdx.x + blockIdx.x * blockDim.x;
    int localIdx  = threadIdx.x;
    int numBlockThreads = (blockIdx.x != numBlocks - 1) ? blockDim.x : (inputLength - ((numBlocks - 1) * blockDim.x));

    if (globalIdx >= inputLength) return; // banish bad threads

    blockInput[localIdx] = inputArray[globalIdx];
    __syncthreads();

    T curr;
    T neww;

    for (int i = 1; i < numBlockThreads; i *= 2) {
        if (localIdx > (i - 1)) {
            curr = blockInput[localIdx - i];
            neww = blockInput[localIdx];
            if (curr < 0) curr = 0;
            if (neww < 0) neww = 0;
            if (min) blockInput[localIdx] = (neww < curr) ? neww : curr;
            else blockInput[localIdx] = (neww > curr) ? neww : curr;
            __syncthreads();
        }
    }

    int last = numBlockThreads - 1;
    if (localIdx == last) blockwiseExtrema[blockIdx.x] = blockInput[last];
}

__global__ void colorImage(unsigned char* image, int* iterations, int nCols, int inputSize, double minIter, double maxIter, double minHue, double maxHue)
{
	int x = threadIdx.x + blockIdx.x * blockDim.x;
	int y = threadIdx.y + blockIdx.y * blockDim.y;
	int globalIdx = x + y * nCols;
	if (globalIdx >= inputSize) {return;}; // banish bad threads
	if (iterations[globalIdx] < 0) {return;}; // banish threads for areas that should be black

	double H = minHue + ((iterations[globalIdx] - minIter) / (maxIter - minIter)) * (maxHue - minHue);
	double S = 1;
	double V = 1;

	while (H < 0) {H += 360; };
	while (H >= 360) {H -= 360; };
	double R, G, B;
	if (V <= 0) {
		R = 0;
		G = 0;
		B = 0;
	}
	else if (S <= 0) {
		R = G = B = V;
	}
	else
	{
		double hf = H / 60.0;
		int i = (int) floor(hf);
		double f = hf - i;
		double pv = V * (1 - S);
		double qv = V * (1 - S * f);
		double tv = V * (1 - S * (1 - f));

		switch (i) {
	      	 // Red is the dominant color
	    	case 0:
	    		R = V;
	      		G = tv;
	      		B = pv;
	        break;
	        // Green is the dominant color
	    	case 1:
	    		R = qv;
	    		G = V;
	    		B = pv;
	    		break;
	    	case 2:
	    		R = pv;
	    		G = V;
	    		B = tv;
	    		break;
	    	// Blue is the dominant color
	    	case 3:
	    		R = pv;
	    		G = qv;
	    		B = V;
	    		break;
	    	case 4:
	    		R = tv;
	    		G = pv;
	    		B = V;
	    		break;
	    	// Red is the dominant color
	    	case 5:
	    		R = V;
	    		G = pv;
	    		B = qv;
	    		break;
	    	// Just in case we overshoot on our math by a little, we put these here. Since its a switch it won't slow us down at all to put these here.
	    	case 6:
	    		R = V;
	    		G = tv;
	    		B = pv;
	    		break;
	    	case -1:
	    		R = V;
	    		G = pv;
	    		B = qv;
	    		break;
	    	// The color is not defined, we should throw an error.
	    	default:
	    	  //LFATAL("i Value error in Pixel conversion, Value is %d", i);
	    	  R = G = B = V; // Just pretend its black/white
	    	  break;
		}
	}
	unsigned char r = (unsigned char) (R * 255.0);
	unsigned char g = (unsigned char) (G * 255.0);
	unsigned char b = (unsigned char) (B * 255.0);

	if (r > 255) r = 255;
	if (g > 255) g = 255;
	if (b > 255) b = 255;

	image[3 * globalIdx    ] = b;
	image[3 * globalIdx + 1] = g;
	image[3 * globalIdx + 2] = r;
}

void render(unsigned char* h_image, double x0, double y0, double xD, double yD, int nCols, int nRows, int limitIter)
{
	int pointsPerBlock = 32;

	// Determine kernel properties
	dim3 threadDims(pointsPerBlock, pointsPerBlock);
	int xBlocks = nCols / pointsPerBlock;
	int yBlocks = nRows / pointsPerBlock;
	if (nCols % pointsPerBlock != 0) xBlocks++;
	if (nRows % pointsPerBlock != 0) yBlocks++;
	dim3 blockDims(xBlocks, yBlocks);

	int* d_iterations;
	cudaMalloc(&d_iterations, nCols * nRows * sizeof(int));
	getIterationCounts<<<blockDims, threadDims>>>(x0, y0, xD, yD, nCols, nRows, limitIter, d_iterations);
	cudaDeviceSynchronize();
	printf("Calculated iteration counts\n");

	int nThreads = threadDims.x * threadDims.y;
	int nBlocks = (nCols * nRows) / nThreads;
	if (nThreads % (nCols * nRows) != 0) nBlocks++;
	int* blockwiseExtrema;
	cudaMalloc(&blockwiseExtrema, nBlocks * sizeof(int));

	/*
	int* d_min; // Error in oversizing the grid size
	int h_min[1];
	cudaMalloc(&d_min, sizeof(int));
	getBlockwiseExtrema<int><<<nBlocks, nThreads, nThreads * sizeof(int)>>>(d_iterations, blockwiseExtrema, nCols * nRows, nBlocks, true);
	cudaDeviceSynchronize();
	getBlockwiseExtrema<int><<<1, nBlocks, nBlocks * sizeof(int)>>>(blockwiseExtrema, d_min, nBlocks, 1, true);
	cudaDeviceSynchronize();
	cudaMemcpy(h_min, d_min, sizeof(int), cudaMemcpyDeviceToHost);

	int* d_max;
	int h_max[1];
	cudaMalloc(&d_max, sizeof(int));
	getBlockwiseExtrema<int><<<nBlocks, nThreads, nThreads * sizeof(int)>>>(d_iterations, blockwiseExtrema, nCols * nRows, nBlocks, false);
	cudaDeviceSynchronize();
	getBlockwiseExtrema<int><<<1, nBlocks, nBlocks * sizeof(int)>>>(blockwiseExtrema, d_max, nBlocks, 1, false);
	cudaDeviceSynchronize();
	cudaMemcpy(h_max, d_max, sizeof(int), cudaMemcpyDeviceToHost);
	printf("Calculated iteration range\n");

	double minIter = (double) h_min[0];
	double maxIter = (double) h_max[0];
	*/

	// manual ovverride of min / max
	double minIter = 0;
	double maxIter = limitIter;

	unsigned char* d_image;
	cudaMalloc(&d_image, 3 * nCols * nRows * sizeof(unsigned char));
	cudaMemset(d_image, 0, 3 * nCols * nRows * sizeof(unsigned char));
	printf("Allocated memory for image\n");
	colorImage<<<blockDims, threadDims>>>(d_image, d_iterations, nCols, nCols * nRows, minIter, maxIter, 0.0, 200.0);
	cudaDeviceSynchronize();
	printf("Colored image\n");
	cudaMemcpy(h_image, d_image, 3 * nCols * nRows * sizeof(unsigned char), cudaMemcpyDeviceToHost);
	printf("Moved image to host\n");

    /* DEBUG iteration count
	int h_iterations[nCols * nRows];
	cudaMemcpy(h_iterations, d_iterations, nCols * nRows * sizeof(int), cudaMemcpyDeviceToHost);
	for (int i = 0; i < nRows; i++) {
		for (int j = 0; j < nCols; j++) {
			printf("%3d", h_iterations[j + i * nCols]);
		}
		printf("\n");
	}
	printf("\n\n");
	*/

	/* DEBUG min/max
	printf("Min: %d\n", h_min[0]);
	printf("Max: %d\n\n\n", h_max[0]);
	*/

	/* DEBUG image gneration
	for (int i = 0; i < nRows; i++) {
		for (int j = 0; j < nCols; j++) {
			printf("[");
			for (int k = 0; k < 3; k++) {
				printf("%3u ", h_image[3 * (j + i * nCols) + k]);
			}
			printf("] ");
		}
		printf("\n");
	}
	printf("\n\n");
	*/
}

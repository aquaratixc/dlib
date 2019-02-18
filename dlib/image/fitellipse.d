module dlib.image.fitellipse;

import std.stdio;
import std.algorithm;
import std.algorithm.searching;
import std.algorithm.iteration: sum;
import std.math;

import dlib.image.measure;

T[][] diagFromVec(T)(T[] v){
    size_t len = v.length;
    T[][] d = new T[][](len, len);
    
    foreach(y; 0..len)
        foreach(x; 0..len){
                d[y][x] = 0;
                if (y == x){
                    d[y][x] = v[x];
                }
                else
                    d[y][x] = 0;
        }
    
    return d;
}

T[] diagOfMat(T)(T[][] m){
    size_t len = m.length;
    
    T[] d; d.length = len;
    
    foreach(y; 0..len)
        foreach(x; 0..len){
            if (y == x) d[x] = m[y][x];
        }
    return d;
}

T[][] transposeMat(T)(T[][] m){
    size_t srows = m.length;
    size_t scols = m[0].length;
    T[][] transpArray = new T[][](scols, srows);


    foreach(i; 0..srows)
        foreach(j; 0..scols)
            transpArray[j][i]= m[i][j];
    return transpArray;
}

T[][] mulMats(T)(T[][] a, T[][] b){
    
    size_t r1 = a.length;
    size_t c1 = a[0].length;
    
    size_t r2 = b.length;
    size_t c2 = b[0].length;
    
    assert (c1 == r2); // column of first matrix in not equal to row of second matrix
    
    T[][] mult = new T[][](r1, c2);
    
    foreach(i; 0..r1)
        foreach(j; 0..c2){
            mult[i][j] = 0;
        }
    
    foreach(i; 0..r1)
        foreach(j; 0..c2)
            foreach(k; 0..c1){
                mult[i][j] += a[i][k] * b[k][j];
            }
    
    return mult;
}

void getCofactor(T)(T[][] A, T[][] temp, int p, int q, ulong n) { 
    int i = 0, j = 0; 
  
    for (int row = 0; row < n; row++) 
    { 
        for (int col = 0; col < n; col++) 
        {  
            if (row != p && col != q) 
            { 
                temp[i][j++] = A[row][col]; 
  
                if (j == n - 1) 
                { 
                    j = 0; 
                    i++; 
                } 
            } 
        } 
    } 
} 

double determinant(T)(T[][] A, ulong n) 
{ 
    size_t N = A.length;
    double D = 0;
  
    
    if (n == 1) 
        return A[0][0]; 
  
    T[][] temp = new T[][](N, N);
  
    int sign = 1;
    
    for (int f = 0; f < n; f++) 
    {
        getCofactor(A, temp, 0, f, n); 
        D += sign * A[0][f] * determinant(temp, n - 1); 
        sign = -sign; 
    } 
  
    return D; 
}

void adjoint(T)(T[][] A, T[][] adj) 
{ 
    size_t N = A.length;
    
    if (N == 1) 
    { 
        adj[0][0] = 1; 
        return; 
    } 
  
    int sign = 1;
    T[][] temp = new T[][](N, N); 
  
    for (int i=0; i<N; i++) 
    { 
        for (int j=0; j<N; j++) 
        { 
            
            getCofactor(A, temp, i, j, N); 
            sign = ((i+j)%2==0)? 1: -1; 
            adj[j][i] = (sign)*(determinant(temp, N-1)); 
        } 
    } 
} 

T[][] inverse(T)(T[][] A) 
{ 
    // https://www.geeksforgeeks.org/adjoint-inverse-matrix/
    size_t N = A.length;
    T[][] inv = new T[][](N, N);
     
    double det = determinant(A, N); 
    assert (det != 0); //  Singular matrix, can't find its inverse
  
    // Find adjoint 
    T[][] adj = new T[][](N, N);
    adjoint(A, adj);
    
    for (int i=0; i<N; i++) 
        for (int j=0; j<N; j++) 
            inv[i][j] = adj[i][j]/float(det); 
  
    return inv; 
}

Tuple!(double[][], double[][])
svd2x2(T)(T[][] A){
    //calculate U, Q, V
    
    T a, b, c, d;
    
    a = A[0][0];
    b = A[0][1];
    c = A[1][0];
    d = A[1][1];
    
    auto Su = mulMats(A, transposeMat(A));
    auto phi = 0.5*atan2(b+c, a-d);
    auto Cphi = cos(phi);
    auto Sphi = sin(phi);
    
    double[][] U = [[Cphi, -Sphi], [Sphi, Cphi]];

    
    auto Sw = mulMats(transposeMat(A), A);
    auto theta = 0.5*atan2(Sw[0][1]+Sw[1][0], Sw[0][0]-Sw[1][1]);
    auto Ctheta = cos(theta);
    auto Stheta = sin(theta);
    double[][] W = [[Ctheta, -Stheta], [Stheta, Ctheta]];

    auto SUsum= Su[0][0]+Su[1][1];
    auto SUdif= sqrt((Su[0][0]-Su[1][1])^^2 + 4*Su[0][1]*Su[1][0]);
    double[] svals= [sqrt((SUsum+SUdif)/2), sqrt((SUsum-SUdif)/2)];
    
    auto Q = diagFromVec(svals);

    auto S = mulMats(mulMats(transposeMat(U),A), W);
    
    double[] tmp = [sgn(S[0][0]), sgn(S[1][1])];
    
    auto C = diagFromVec(tmp);
    auto V = mulMats(W, C); // orientation matrix
    
    return tuple(Q, V);
}

import std.typecons;

Ellipse ellipseFit(XYList xylist){
    /*
    this is implemented using a matlab based approach, and not fast enough.
    we need a faster ellipse fitting code probably. This one takes about 0.1 s.
    
    https://stackoverflow.com/questions/1768197/bounding-ellipse/1768440#1768440
    */
    double tolerance = 0.2;
    double err = 1;
    int count = 1;
    
    int[] xs = xylist.xs;
    int[] ys = xylist.ys;
    
    int npts = cast(int)xylist.xs.length;
    
    double[][] P_T = new double[][](npts, 2);
    foreach(i; 0..npts)
        P_T[i] = [xylist.xs[i], xylist.ys[i]];
    double[][] P = transposeMat(P_T);
    
    double[][] Q_T = new double[][](npts, 3);
    foreach(i; 0..npts)
        Q_T[i] = [xylist.xs[i], xylist.ys[i], 1];
    
    double[][] Q = transposeMat(Q_T);
    
    double[] u; u.length = npts;
    u[0..$] = 1/cast(double)npts;
    
    int d = 2;
    
    while(err > tolerance){
        
        double[][] X = mulMats(mulMats(Q, diagFromVec(u)), Q_T);
        
        double[] M = diagOfMat(mulMats(mulMats(Q_T, inverse(X)), Q));
        
        double maximum = M.maxElement;
        long j = M.maxIndex;
        
        double step_size = (maximum - d -1)/((d+1)*(maximum-1));
        
        double[] new_u; new_u.length = npts;
        foreach(k; 0..npts) new_u[k] = (1 - step_size)*u[k];
        
        double[] diff_u; diff_u.length = npts;
        foreach(k; 0..npts) diff_u[k] =  new_u[k] - u[k];
        
        foreach(i; 0..npts)
            diff_u[i] *= diff_u[i];
        
        err = sqrt(sum(diff_u));
        
        count++;
        u = new_u;
        
    }
    
    double[][] U = diagFromVec(u);
    
    double[][] uM = new double[][](npts, 1);
    foreach(i; 0..npts) uM[i][0] = u[i];
    
    double[][] leftterm = mulMats(mulMats(P, U), P_T);
    double[][] rightterm =  mulMats(mulMats(P, uM), transposeMat(mulMats(P, uM)));
    
    size_t rowsA = leftterm.length;
    size_t colsA = leftterm[0].length;
    
    double[][] _A = new double[][](rowsA, colsA);
    foreach(i; 0.._A.length)
        foreach(j; 0.._A[0].length)
            _A[i][j] = leftterm[i][j] - rightterm[i][j];
    
    double[][] A = inverse(_A);
    
    foreach(i; 0..A.length)
        foreach(j; 0..A[0].length)
            A[i][j] *= 1.0 / cast(double)d;
    
    double[][] C = mulMats(P, uM);
    
    auto _Q_V = svd2x2(A);
    auto _Q = _Q_V[0];
    auto _V = _Q_V[1]; // rotation matrix
    
    double orientation = atan2(_V[1][0], _V[0][0]); // this seems wrong TODO: fix
    double r1 = 1/sqrt(_Q[0][0]); 
    double r2 = 1/sqrt(_Q[1][1]); 
    
    auto centerx = C[0][0];
    auto centery = C[1][0];
    
    return Ellipse(orientation, centerx, centery, r1, r2);
    
}

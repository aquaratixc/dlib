/*
Copyright (c) 2013-2015 Timur Gafarov 

Boost Software License - Version 1.0 - August 17th, 2003

Permission is hereby granted, free of charge, to any person or organization
obtaining a copy of the software and accompanying documentation covered by
this license (the "Software") to use, reproduce, display, distribute,
execute, and transmit the Software, and to prepare derivative works of the
Software, and to permit third-parties to whom the Software is furnished to
do so, all subject to the following:

The copyright notices in the Software and this entire statement, including
the above license grant, this restriction and the following disclaimer,
must be included in all copies of the Software, in whole or in part, and
all derivative works of the Software, unless such copies or derivative
works are solely in the form of machine-executable object code generated by
a source language processor.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE, TITLE AND NON-INFRINGEMENT. IN NO EVENT
SHALL THE COPYRIGHT HOLDERS OR ANYONE DISTRIBUTING THE SOFTWARE BE LIABLE
FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER IN CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.
*/

module dlib.image.filters.chromakey;

private
{
    import dlib.math.utils;
    import dlib.image.image;
    import dlib.image.color;
    import dlib.image.hsv;

    import dlib.math.vector;
    import dlib.math.utils;
}

SuperImage chromaKeyEuclidean(
    SuperImage img, 
    Color4f keyColor, 
    float minDist,
    float maxDist)
{
    return chromaKeyEuclidean(img, null, keyColor, minDist, maxDist);
}

SuperImage chromaKeyEuclidean(
    SuperImage img, 
    SuperImage outp,
    Color4f keyColor, 
    float minDist,
    float maxDist)
{
    SuperImage res;
    if (outp)
        res = outp;
    else
        res = img.dup;
   
    foreach(y; img.col)
    foreach(x; img.row)
    {       
        Color4f col = img[x, y];
        
        Color4f delta = col - keyColor;
        float distSqr = dot(delta, delta);
        col.a = clamp(
            (distSqr - minDist) / (maxDist - minDist), 
            0.0f, 1.0f);
        res[x, y] = col;
        
        img.updateProgress();
    }
    
    img.resetProgress();
    
    return res;
}

SuperImage chromaKey(
    SuperImage img, 
    float hue,
    float hueToleranceMin = -20.0f, 
    float hueToleranceMax = 20.0f, 
    float satThres = 0.2f,
    float valThres = 0.3f)
{
    return chromaKey(img, null, hue, hueToleranceMin, hueToleranceMax, satThres, valThres);
}

SuperImage chromaKey(
    SuperImage img,
    SuperImage outp,
    float hue,
    float hueToleranceMin = -20.0f, 
    float hueToleranceMax = 20.0f, 
    float satThres = 0.2f,
    float valThres = 0.3f)
{
    SuperImage res;
    if (outp)
        res = outp;
    else
        res = img.dup;

    foreach(x; 0..img.width)
    foreach(y; 0..img.height)
    {
        Color4f col = res[x, y];
        ColorHSVAf hsva = ColorHSVAf(col);
        
        hsva.selectiveScale(
            hue,
            HSVAChannel.A,
            0.0f,
            false,
            hueToleranceMin,
            hueToleranceMax,
            satThres,
            valThres);

        res[x, y] = hsva.rgba;
        
        img.updateProgress();
    }
    
    img.resetProgress();

    return res;
}

/*
 * Turns image into b&w where only one color left
 */
SuperImage colorPass(
    SuperImage img, 
    float hue,
    float hueToleranceMin = -20.0f, 
    float hueToleranceMax = 20.0f, 
    float satThres = 0.2f,
    float valThres = 0.3f)
{
    return colorPass(img, null, hue, hueToleranceMin, hueToleranceMax, satThres, valThres);
}
 
SuperImage colorPass(
    SuperImage img,
    SuperImage outp,
    float hue,
    float hueToleranceMin = -20.0f, 
    float hueToleranceMax = 20.0f, 
    float satThres = 0.2f,
    float valThres = 0.3f)
in
{
    assert (img.data.length);
}
body
{
    SuperImage res;
    if (outp)
        res = outp;
    else
        res = img.dup;
    
    foreach(y; 0..img.height)
    foreach(x; 0..img.width)
    {
        Color4f col = res[x, y];
        ColorHSVAf hsva = ColorHSVAf(col);
        hsva.selectiveScale(
            hue, 
            HSVAChannel.S, 
            0.0f, 
            true, 
            hueToleranceMin, 
            hueToleranceMax, 
            satThres, 
            valThres);
        
        res[x, y] = hsva.rgba;
        
        img.updateProgress();
    }
    
    img.resetProgress();
    
    return res;
}

private:

void selectiveScale(ref ColorHSVAf col,
                    float hue,
                    HSVAChannel chan,
                    float scale,
                    bool inverse,
                    float hueToleranceMin = -20.0f, 
                    float hueToleranceMax = 20.0f, 
                    float satThres = 0.2f,
                    float valThres = 0.3f)
{
    while (hue >= 360.0f) 
        hue -= 360.0f;
    while (hue < 0.0f) 
        hue += 360.0f;

    if (col.hueInRange(hue, hueToleranceMin, hueToleranceMax) 
        && col.s > satThres 
        && col.v > valThres)
    {
        if (!inverse)
            col.arrayof[chan] *= scale;
    }
    else
    {
        if (inverse)          
            col.arrayof[chan] *= scale;
    }
}


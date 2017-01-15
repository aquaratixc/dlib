/*
Copyright (c) 2011-2017 Timur Gafarov

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

module dlib.image.filters.normalmap;

private
{
    import dlib.image.image;
    import dlib.image.color;
    import dlib.math.vector;
}

/*
 * Generate normal map from height map
 * using Sobel operator
 *
 * TODO: optionally transfer height data to alpha channel
 */

SuperImage heightToNormal(
    SuperImage img,
    Channel channel = Channel.R,
    float strength = 2.0f)
{
    return heightToNormal(img, null, channel, strength);
}

SuperImage heightToNormal(
    SuperImage img,
    SuperImage outp,
    Channel channel = Channel.R,
    float strength = 2.0f)
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

    if (img.channels == 1)
        channel = Channel.R;

    float[8] sobelTaps;

    foreach(y; 0..img.height)
    foreach(x; 0..img.width)
    {
        sobelTaps[0] = img[x-1, y-1][channel];
        sobelTaps[1] = img[x,   y-1][channel];
        sobelTaps[2] = img[x+1, y-1][channel];
        sobelTaps[3] = img[x-1, y+1][channel];
        sobelTaps[4] = img[x,   y+1][channel];
        sobelTaps[5] = img[x+1, y+1][channel];
        sobelTaps[6] = img[x-1, y  ][channel];
        sobelTaps[7] = img[x+1, y  ][channel];

        float dx, dy;

        // Do y sobel filter
        dy  = sobelTaps[0] * +1.0f;
        dy += sobelTaps[1] * +2.0f;
        dy += sobelTaps[2] * +1.0f;
        dy += sobelTaps[3] * -1.0f;
        dy += sobelTaps[4] * -2.0f;
        dy += sobelTaps[5] * -1.0f;

        // Do x sobel filter
        dx  = sobelTaps[0] * -1.0f;
        dx += sobelTaps[6] * -2.0f;
        dx += sobelTaps[3] * -1.0f;
        dx += sobelTaps[2] * +1.0f;
        dx += sobelTaps[7] * +2.0f;
        dx += sobelTaps[5] * +1.0f;

        // pack normal into floating-point RGBA
        Vector3f normal = Vector3f(-dx, -dy, 1.0f / strength);
        Color4f col = packNormal(normal);
        col.a = 1.0f;

        // write result
        res[x, y] = col;

        img.updateProgress();
    }

    img.resetProgress();

    return res;
}

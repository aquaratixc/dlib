/*
Copyright (c) 2014 Timur Gafarov 

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

module dlib.image.io.bmp;

private
{
    import std.stdio;
    import std.c.stdio;

    import dlib.image.image;
    import dlib.image.color;
    import dlib.image.io.io;
    import dlib.image.io.utils;

    import dlib.core.stream;
    import dlib.filesystem.functions;
}

// uncomment this to see debug messages:
//version = BMPDebug;

static const ubyte[2] BMPMagic = ['B', 'M'];

struct BMPFileHeader
{
    ubyte[2] type;        // magic number "BM"
    uint size;            // file size
    ushort reserved1; 
    ushort reserved2;
    uint offset;          // offset to image data
}

struct BMPInfoHeader
{
    uint size;            // size of bitmap info header
    int width;            // image width
    int height;           // image height
    ushort planes;        // must be equal to 1
    ushort bitsPerPixel;  // bits per pixel
    uint compression;     // compression type
    uint imageSize;       // size of pixel data
    int xPixelsPerMeter;  // pixels per meter on x-axis
    int yPixelsPerMeter;  // pixels per meter on y-axis
    uint colorsUsed;      // number of used colors
    uint colorsImportant; // number of important colors
}

struct BMPCoreHeader
{
    uint size;            // size of bitmap core header
    ushort width;         // image with
    ushort height;        // image height
    ushort planes;        // must be equal to 1
    ushort bitsPerPixel;  // bits per pixel
}

struct BMPCoreInfo
{
    BMPCoreHeader header;
    ubyte[3] colors;
}

enum BMPOSType
{
    Win,
    OS2
}

// BMP compression type constants
enum BMPCompressionType
{
    RGB          = 0,
    RLE8         = 1,
    RLE4         = 2,
    BitFields    = 3
}

// RLE byte type constants
enum RLE
{
    Command      = 0,
    EndOfLine    = 0,
    EndOfBitmap  = 1,
    Delta        = 2
}

int getPos(File* f)
{
    int pos;
    fgetpos(f.getFP, &pos);
    return pos;
}

void setPos(File* f, int pos)
{
    fsetpos(f.getFP, &pos);
}

class BMPLoadException: ImageLoadException
{
    this(string msg, string file = __FILE__, size_t line = __LINE__, Throwable next = null)
    {
        super(msg, file, line, next);
    }
}

SuperImage loadBMP(string filename)
{
    InputStream input = openForInput(filename);
    
    try
    {
        return loadBMP(input);
    }
    catch (BMPLoadException ex)
    {
        throw new Exception("'" ~ filename ~ "' :" ~ ex.msg, ex.file, ex.line, ex.next);
    }
    finally
    {
        input.close();
    }
}

SuperImage loadBMP(InputStream input)
{
    SuperImage img;

    BMPFileHeader bmpfh;
    BMPInfoHeader bmpih;
    BMPCoreHeader bmpch;

    BMPOSType osType;

    uint compression;
    uint bitsPerPixel;

    ubyte[] colormap;
    int colormapSize;

    bmpfh = readStruct!BMPFileHeader(input);

    auto bmphPos = input.position;

    version(BMPDebug)
    { 
        writefln("bmpfh.type = %s", cast(char[])bmpfh.type);
        writefln("bmpfh.size = %s", bmpfh.size);
        writefln("bmpfh.reserved1 = %s", bmpfh.reserved1);
        writefln("bmpfh.reserved2 = %s", bmpfh.reserved2);
        writefln("bmpfh.offset = %s", bmpfh.offset);
        writeln("-------------------"); 
    }

    if (bmpfh.type != BMPMagic)
        throw new BMPLoadException("BMP error: input data is not BMP");

    uint numChannels = 3;
    uint width, height;

    bmpih = readStruct!BMPInfoHeader(input);

    version(BMPDebug)
    { 
        writefln("bmpih.size = %s", bmpih.size);
        writefln("bmpih.width = %s", bmpih.width);
        writefln("bmpih.height = %s", bmpih.height);
        writefln("bmpih.planes = %s", bmpih.planes);
        writefln("bmpih.bitsPerPixel = %s", bmpih.bitsPerPixel);
        writefln("bmpih.compression = %s", bmpih.compression);
        writefln("bmpih.imageSize = %s", bmpih.imageSize);
        writefln("bmpih.xPixelsPerMeter = %s", bmpih.xPixelsPerMeter);
        writefln("bmpih.yPixelsPerMeter = %s", bmpih.yPixelsPerMeter);
        writefln("bmpih.colorsUsed = %s", bmpih.colorsUsed);
        writefln("bmpih.colorsImportant = %s", bmpih.colorsImportant);
        writeln("-------------------"); 
    }

    if (bmpih.compression > 3)
    {
        /* 
         * This is an OS/2 bitmap file, we don't use
         * bitmap info header but bitmap core header instead
         */

        // We must go back to read bitmap core header
        input.position = bmphPos;
        bmpch = readStruct!BMPCoreHeader(input);

        osType = BMPOSType.OS2;
        compression = BMPCompressionType.RGB;
        bitsPerPixel = bmpch.bitsPerPixel;

        width = bmpch.width;
        height = bmpch.height;
    }
    else
    {
        // Windows style
        osType = BMPOSType.Win;
        compression = bmpih.compression;
        bitsPerPixel = bmpih.bitsPerPixel;

        width = bmpih.width;
        height = bmpih.height;
    }

    version(BMPDebug)
    { 
        writefln("osType = %s", [BMPOSType.OS2: "OS/2", BMPOSType.Win: "Windows"][osType]);
        writefln("width = %s", width);
        writefln("height = %s", height);
        writefln("bitsPerPixel = %s", bitsPerPixel);
        writefln("compression = %s", compression);
        writeln("-------------------"); 
    }

    // get the padding at the end of the bitmap
    uint pitch = width * 3; // 3 since it's 24 bits, or 3 bytes per pixel
    if (pitch % 4 != 0)
    {
        pitch += 4 - (pitch % 4);
    }

    uint padding = pitch - (width * 3); // this is how many bytes of padding we need
    version(BMPDebug)
    {
        writefln("pitch = %s", pitch);
        writefln("padding = %s", padding);
    }

    if (compression != BMPCompressionType.RGB)
        throw new BMPLoadException("BMP error: only RGB images are supported by decoder");

    if (bitsPerPixel != 24)
        throw new BMPLoadException("BMP error: unsupported color depth");

    // Create image
    uint channels = bmpih.bitsPerPixel / 8;
    img = image(width, height, channels);

    // Look for palette data if present
    if (bitsPerPixel <= 8)
    {
        colormapSize = (1 << bitsPerPixel) * ((osType == BMPOSType.OS2)? 3 : 4);
        colormap = new ubyte[colormapSize];

        input.fillArray(colormap);
    }

    // Go to begining of pixel data
    input.position = bmpfh.offset;

    // Read image data
    switch (compression)
    {
        case BMPCompressionType.RGB:
            switch (bitsPerPixel)
            {
                case 1:
                    // TODO
                    break;

                case 4:
                    // TODO
                    break;

                case 8:
                    // TODO
                    break;

                case 24:
                    read24bitBMP(input, img, padding);
                    break;

                case 32:
                    // TODO
                    break;

                default:
                    break;
            }
            break;

        case BMPCompressionType.RLE8:
            // TODO
            break;

        case BMPCompressionType.RLE4:
            // TODO
            break;

        case BMPCompressionType.BitFields:
            // TODO
            break;

        default:
            // Unsupported file types
            throw new BMPLoadException("BMP error: unsupported bitmap compression type");
    }

    return img;
}

void read24bitBMP(InputStream input, SuperImage img, uint padding)
{
    foreach(y; 0..img.height)
    {
        foreach(x; 0..img.width)
        {
            ubyte[3] bgr;
            input.fillArray(bgr);
            img[x, y] = Color4f(ColorRGBA(bgr[2], bgr[1], bgr[0]));
        }

        input.seek(padding);
    }
}

void saveBMP(SuperImage img, string filename)
{
    assert(0, "Saving to BMP is not yet implemented");   
}

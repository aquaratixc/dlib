/*
Copyright (c) 2016-2017 Timur Gafarov

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

module dlib.math.tensor;

import std.traits;
import std.math;
import std.conv;
import std.range;
import std.format;

import dlib.core.tuple;
import dlib.core.compound;

T zero(T)() if (isNumeric!T)
{
    return T(0);
}

size_t calcLen(T...)(T n)
{
    size_t len = 1;
    foreach(s; n)
        len *= s;
    return len;
}

template NTypeTuple(T, int n)
{
    static if (n <= 0)
        alias Tuple!() NTypeTuple;
    else
        alias Tuple!(NTypeTuple!(T, n-1), T) NTypeTuple;
}

enum MaxStaticTensorSize = double.sizeof * 16; // fit 4x4 matrix of doubles

/*
 * Generic multi-dimensional array template.
 * It mainly serves as a base for creating various
 * more specialized algebraic objects via encapsulation.
 * Think of Tensor as a backend for e.g. Vector and Matrix.
 *
 * T - element type, usually numeric (float or double)
 * dim - number of dimensions (tensor order):
 *    0 - scalar
 *    1 - vector
 *    2 - matrix
 *    3 - 3D array
 *    (higer dimensions are also possible)
 * sizes - tuple defining sizes for each dimension:
 *    3 - 3-vector
 *    4,4 - 4x4 matrix
 *    etc.
 *
 * Data storage type (stack or heap) is statically selected: if given size(s)
 * imply data size larger than MaxStaticTensorSize, data is allocated
 * on heap (as dynamic array). Otherwise, data is allocated on stack (as static array).
 */

// TODO:
// - Manual memory management
// - External storage
// - Component-wise addition, subtraction

template Tensor(T, size_t dim, sizes...)
{
    struct Tensor
    {
        private enum size_t _dataLen = calcLen(sizes);

        alias T ElementType;
        enum size_t dimensions = dim;
        enum size_t order = dim;
        alias sizes Sizes;
        enum bool isTensor = true;
        enum bool isScalar = (order == 0 && _dataLen == 1);
        enum bool isVector = (order == 1);
        enum bool isMatrix = (order == 2);
        enum bool dynamic = (_dataLen * T.sizeof) > MaxStaticTensorSize;

        static assert(order == sizes.length,
                "Illegal size for Tensor");

        static if (order > 0)
        {
            static assert(sizes.length,
                "Illegal size for 0-order Tensor");
        }

        static if (isVector)
        {
            static assert(sizes.length == 1,
                "Illegal size for 1st-order Tensor");
        }

        static if (isMatrix)
        {
            static assert(sizes.length == 2,
                "Illegal size for 2nd-order Tensor");

            enum size_t rows = sizes[0];
            enum size_t cols = sizes[1];

            enum bool isSquareMatrix = (rows == cols);

            static if (isSquareMatrix)
            {
                enum size = sizes[0];
            }
        }
        else
        {
            enum bool isSquareMatrix = false;

            static if (sizes.length > 0)
            {
                enum size = sizes[0];
            }
        }

       /*
        * Single element constructor
        */
        this(T initVal)
        {
            static if (dynamic)
            {
                allocate();
            }

            foreach(ref v; data)
                v = initVal;
        }

       /*
        * Tensor constructor
        */
        this(Tensor!(T, order, sizes) t)
        {
            static if (dynamic)
            {
                allocate();
            }

            foreach(i, v; t.arrayof)
            {
                arrayof[i] = v;
            }
        }

       /*
        * Tuple constructor
        */
        this(F...)(F components) if (F.length > 1)
        {
            static if (dynamic)
            {
                allocate();
            }

            foreach(i, v; components)
            {
                static if (i < arrayof.length)
                    arrayof[i] = cast(T)v;
            }
        }

        static Tensor!(T, order, sizes) init()
        {
            Tensor!(T, order, sizes) res;
            static if (dynamic)
            {
                res.allocate();
            }
            return res;
        }

        static Tensor!(T, order, sizes) zero()
        {
            Tensor!(T, order, sizes) res;
            static if (dynamic)
            {
                res.allocate();
            }
            foreach(ref v; res.data)
                v = .zero!T();
            return res;
        }

       /*
        * T = Tensor[index]
        */
        auto ref T opIndex(this X)(size_t index)
        in
        {
            assert ((0 <= index) && (index < _dataLen),
                "Tensor.opIndex: array index out of bounds");
        }
        body
        {
            return arrayof[index];
        }

       /*
        * Tensor[index] = T
        */
        void opIndexAssign(T n, size_t index)
        in
        {
            assert (index < _dataLen,
                "Tensor.opIndexAssign: array index out of bounds");
        }
        body
        {
            arrayof[index] = n;
        }

       /*
        * T = Tensor[i, j, ...]
        */
        T opIndex(I...)(in I indices) const if (I.length == sizes.length)
        {
            size_t index = 0;
            size_t m = 1;
            foreach(i, ind; indices)
            {
                index += ind * m;
                m *= sizes[i];
            }
            return arrayof[index];
        }

       /*
        * Tensor[i, j, ...] = T
        */
        T opIndexAssign(I...)(in T t, in I indices) if (I.length == sizes.length)
        {
            size_t index = 0;
            size_t m = 1;
            foreach(i, ind; indices)
            {
                index += ind * m;
                m *= sizes[i];
            }
            return (arrayof[index] = t);
        }

       /*
        * Tensor = Tensor
        */
        void opAssign (Tensor!(T, order, sizes) t)
        {
            static if (dynamic)
            {
                allocate();
            }

            foreach(i, v; t.arrayof)
            {
                arrayof[i] = v;
            }
        }

        alias NTypeTuple!(size_t, order) Indices;

        int opApply(scope int delegate(ref T v, Indices indices) dg)
        {
            int result = 0;
            Compound!(Indices) ind;
            size_t index = 0;

            while(index < data.length)
            {
                result = dg(data[index], ind.tuple);
                if (result)
                    break;

                ind[0]++;

                foreach(i; RangeTuple!(0, order))
                {
                    if (ind[i] == sizes[i])
                    {
                        ind[i] = 0;
                        static if (i < order-1)
                        {
                            ind[i+1]++;
                        }
                    }
                }

                index++;
            }

            return result;
        }

        @property string toString() const
        {
            static if (isScalar)
            {
                return x.to!string;
            }
            else
            {
                auto writer = appender!string();
                formattedWrite(writer, "%s", arrayof);
                return writer.data;
            }
        }

        @property size_t length()
        {
            return data.length;
        }

        @property bool initialized()
        {
            return (data.length > 0);
        }

        static if (isVector)
        {
           /*
            * NOTE: unfortunately, the following cannot be
            * moved to Vector struct because of conflicting
            * opDispatch with alias this.
            */

            private static bool valid(string s)
            {
                if (s.length < 2)
                    return false;

                foreach(c; s)
                {
                    switch(c)
                    {
                        case 'w', 'a', 'q':
                            if (size < 4) return false;
                            else break;
                        case 'z', 'b', 'p':
                            if (size < 3) return false;
                            else break;
                        case 'y', 'g', 't':
                            if (size < 2) return false;
                            else break;
                        case 'x', 'r', 's':
                            if (size < 1) return false;
                            else break;
                        default:
                            return false;
                    }
                }
                return true;
            }

            static if (size < 5)
            {
               /*
                * Symbolic element access for vector
                */
                private static string vecElements(string[4] letters) @property
                {
                    string res;
                    foreach (i; 0..size)
                    {
                        res ~= "T " ~ letters[i] ~ "; ";
                    }
                    return res;
                }
            }

           /*
            * Swizzling
            */
            template opDispatch(string s) if (valid(s))
            {
                static if (s.length <= 4)
                {
                    @property auto ref opDispatch(this X)()
                    {
                        auto extend(string s)
                        {
                            while (s.length < 4)
                                s ~= s[$-1];
                            return s;
                        }

                        enum p = extend(s);
                        enum i = (char c) => ['x':0, 'y':1, 'z':2, 'w':3,
                                              'r':0, 'g':1, 'b':2, 'a':3,
                                              's':0, 't':1, 'p':2, 'q':3][c];
                        enum i0 = i(p[0]),
                             i1 = i(p[1]),
                             i2 = i(p[2]),
                             i3 = i(p[3]);

                        static if (s.length == 4)
                            return Tensor!(T,1,4)(arrayof[i0], arrayof[i1], arrayof[i2], arrayof[i3]);
                        else static if (s.length == 3)
                            return Tensor!(T,1,3)(arrayof[i0], arrayof[i1], arrayof[i2]);
                        else static if (s.length == 2)
                            return Tensor!(T,1,2)(arrayof[i0], arrayof[i1]);
                    }
                }
            }
        }

        static if (dynamic)
        {
            T[] data;

            private void allocate()
            {
                if (data.length == 0)
                    data = new T[_dataLen];
            }
        }
        else
        {
            union
            {
                T[_dataLen] data;

                static if (isScalar)
                {
                    T x;
                }

                static if (isVector)
                {
                    static if (size < 5)
                    {
                        struct { mixin(vecElements(["x", "y", "z", "w"])); }
                        struct { mixin(vecElements(["r", "g", "b", "a"])); }
                        struct { mixin(vecElements(["s", "t", "p", "q"])); }
                    }
                }
            }

            static if (isScalar)
            {
                alias x this;
            }
        }

        alias data arrayof;

    }
}

/*
 * Tensor product of two tensors of order N
 * and sizes S1 and S2 gives a tensor of order 2N
 * and sizes (S1,S2).
 *
 * TODO: ensure T1, t2 are Tensors
 * TODO: if T1 and T2 are scalars, use ordinary multiplication
 * TODO: if T1 and T2 are vectors, use optimized version
 */
auto tensorProduct(T1, T2)(T1 t1, T2 t2)
{
    static assert(T1.dimensions == T2.dimensions);

    alias T1.ElementType T;
    enum order = T1.dimensions + T2.dimensions;
    alias Tuple!(T2.Sizes, T1.Sizes) sizes;
    alias Tensor!(T, order, sizes) TensorType;

    TensorType t;
    static if (TensorType.dynamic)
    {
        t = TensorType.init();
    }

    Compound!(TensorType.Indices) ind;
    size_t index = 0;

    while(index < t.data.length)
    {
        t.data[index] =
            t2[ind.tuple[0..$/2]] *
            t1[ind.tuple[$/2..$]];

        ind[0]++;

        foreach(i; RangeTuple!(0, order))
        {
            if (ind[i] == sizes[i])
            {
                ind[i] = 0;
                static if (i < order-1)
                {
                    ind[i+1]++;
                }
            }
        }

        index++;
    }

    return t;
}


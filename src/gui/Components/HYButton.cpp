/*
 
 HyPhy - Hypothesis Testing Using Phylogenies.
 
 Copyright (C) 1997-now
 Core Developers:
 Sergei L Kosakovsky Pond (sergeilkp@icloud.com)
 Art FY Poon    (apoon@cfenet.ubc.ca)
 Steven Weaver (sweaver@temple.edu)
 
 Module Developers:
 Lance Hepler (nlhepler@gmail.com)
 Martin Smith (martin.audacis@gmail.com)
 
 Significant contributions from:
 Spencer V Muse (muse@stat.ncsu.edu)
 Simon DW Frost (sdf22@cam.ac.uk)
 
 Permission is hereby granted, free of charge, to any person obtaining a
 copy of this software and associated documentation files (the
 "Software"), to deal in the Software without restriction, including
 without limitation the rights to use, copy, modify, merge, publish,
 distribute, sublicense, and/or sell copies of the Software, and to
 permit persons to whom the Software is furnished to do so, subject to
 the following conditions:
 
 The above copyright notice and this permission notice shall be included
 in all copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
 OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
 CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
 TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
 SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 
 */

#include "HYEventTypes.h"
#include "HYButton.h"
#include "HYGraphicPane.h"

#ifdef    __HYPHYDMALLOC__
#include "dmalloc.h"
#endif
//__________________________________________________________________

_HYButton::_HYButton (_HYRect r,Ptr p):_HYComponent (r,p)
{
    backColor.R = backColor.G = backColor.B = 255;
    buttonFont.style = HY_FONT_PLAIN;
#ifndef __HYPHY_GTK__
    buttonFont.size = 12;
    buttonFont.face = "System Font";
#else
    buttonFont.size = 10;
    buttonFont.face = _HY_SANS_FONT;
#endif
    alignFlags = 0;
    buttonKind = 0;
    isEnabled = true;
}

//__________________________________________________________________

_HYButton::~_HYButton()
{
}

//__________________________________________________________________

void        _HYButton::SetBackColor (_HYColor c)
{
    if ((c.R!=backColor.R)||(c.G!=backColor.G)||(c.B!=backColor.B)) {
        backColor = c;
        _SetBackColor (c);
        _MarkForUpdate();
    }
}

//__________________________________________________________________

_HYColor&       _HYButton::GetBackColor (void)
{
    return backColor;
}

//__________________________________________________________________
void            _HYButton::SetText (_String newText)
{
    buttonText = newText;
    _SetText ();
    _MarkForUpdate();
}

//__________________________________________________________________

_String&        _HYButton::GetText (void)
{
    return buttonText;
}

//__________________________________________________________________

_HYFont&        _HYButton::GetFont (void)
{
    return buttonFont;
}

//__________________________________________________________________

void            _HYButton::SetFont (_HYFont&f)
{
    if ((f.face!=buttonFont.face)||(f.size!=buttonFont.size)||(f.style!=buttonFont.style)) {
        _SetFont (f);
        buttonFont.face = f.face;
        buttonFont.size = f.size;
        buttonFont.style = f.style;
        _MarkForUpdate();
    }
}

//__________________________________________________________________
void            _HYButton::SetVisibleSize (_HYRect rel)
{
    _HYComponent::SetVisibleSize (rel);
    _HYPlatformButton::_SetVisibleSize (rel);
}



//__________________________________________________________________

void            _HYButton::EnableButton (bool e)
{
    if (isEnabled!=e) {
        isEnabled = e;
        _EnableButton (e);
    }
}

//__________________________________________________________________

void            _HYButton::SetButtonKind (unsigned char k)
{
    if (buttonKind != k) {
        buttonKind = k;
        _SetButtonKind (k);
    }
}

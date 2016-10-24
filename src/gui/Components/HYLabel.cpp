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
#include "HYLabel.h"
#include "HYGraphicPane.h"

#ifdef    __HYPHYDMALLOC__
#include "dmalloc.h"
#endif

//__________________________________________________________________

_HYLabel::_HYLabel(_HYRect r,Ptr p):_HYComponent (r,p)
{
    backColor.R = backColor.G = backColor.B = 255;
    foreColor.R = foreColor.G = foreColor.B = 0;
    labelFont.size = 9;
    labelFont.style = HY_FONT_PLAIN;
    labelFont.face = "Monaco";
    alignFlags = 0;
    visFlags = 0;
}

//__________________________________________________________________

_HYLabel::~_HYLabel()
{
}

//__________________________________________________________________
void        _HYLabel::SetBackColor (_HYColor c)
{
    if ((c.R!=backColor.R)||(c.G!=backColor.G)||(c.B!=backColor.B)) {
        backColor = c;
        _SetBackColor (c);
        _MarkForUpdate();
    }
}


//__________________________________________________________________

_HYColor&       _HYLabel::GetBackColor (void)
{
    return backColor;
}

//__________________________________________________________________
void        _HYLabel::SetForeColor (_HYColor c)
{
    if ((c.R!=foreColor.R)||(c.G!=foreColor.G)||(c.B!=foreColor.B)) {
        foreColor = c;
        _SetForeColor (c);
        _MarkForUpdate();
    }
}

//__________________________________________________________________

_HYColor&       _HYLabel::GetForeColor (void)
{
    return foreColor;
}

//__________________________________________________________________
void        _HYLabel::SetText (_String newText)
{
    if (labelText.Equal(&newText)) {
        return;
    }

    labelText = newText;
    _SetText ();
    _MarkForUpdate();
}

//__________________________________________________________________

_String&        _HYLabel::GetText (void)
{
    return labelText;
}

//__________________________________________________________________

_HYFont&        _HYLabel::GetFont (void)
{
    return labelFont;
}

//__________________________________________________________________

void        _HYLabel::SetShadow (bool toggle)
{
    if (toggle) {
        if (!(HY_LABEL_SHADOW&visFlags)) {
            visFlags|=HY_LABEL_SHADOW;
            _MarkForUpdate();
        }
    } else {
        if (HY_LABEL_SHADOW&visFlags) {
            visFlags&=(0xff-HY_LABEL_SHADOW);
            _MarkForUpdate();
        }
    }
}

//__________________________________________________________________

void            _HYLabel::SetFont (_HYFont&f)
{
    if ((f.face!=labelFont.face)||(f.size!=labelFont.size)||(f.style!=labelFont.style)) {
        _SetFont (f);
        labelFont.face = f.face;
        labelFont.size = f.size;
        labelFont.style = f.style;
        _HYPlatformLabel::_SetVisibleSize (rel);
        _MarkForUpdate();
    }
}

//__________________________________________________________________
void        _HYLabel::SetVisibleSize     (_HYRect rel)
{
    _HYComponent::SetVisibleSize (rel);
    _HYPlatformLabel::_SetVisibleSize (rel);
}

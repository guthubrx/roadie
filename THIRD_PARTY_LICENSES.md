# Third-party licenses

This project (`roadie`, MIT-licensed) incorporates code adapted from the
following MIT-licensed projects. Their original copyright notices and full
license texts are reproduced verbatim below, in compliance with the MIT
license attribution requirement.

The intellectual debt to these projects is extensive — see the project
README for a discussion of what was borrowed and why.

---

## yabai

- Project : https://github.com/koekeishiya/yabai
- Author  : Åsmund Vikane
- Adapted in roadie :
  - Window activation pattern (`Sources/RoadieCore/WindowActivator.swift`)
  - Click-to-raise combo (`Sources/RoadieCore/MouseRaiser.swift`)
  - SkyLight space lookup pattern (`Sources/RoadieCore/SkyLightBridge.swift`)
  - Various idiomatic patterns (zoom-fullscreen, balance, focus follows)

```
The MIT License (MIT)

Copyright (c) 2019 Åsmund Vikane

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

## AeroSpace

- Project : https://github.com/nikitabobko/AeroSpace
- Author  : Nikita Bobko
- Adapted in roadie :
  - Hide-in-corner algorithm — **literal reproduction** (`Sources/RoadieCore/HideStrategy.swift`)
  - Virtual desktop pivot architecture (`Sources/RoadieDesktops/Module.swift`)
  - AX event loop pattern (`Sources/RoadieCore/AXEventLoop.swift`)
  - Boot recovery scheme (`Sources/RoadieCore/BootRecovery.swift`)

```
MIT License

Copyright (c) 2023 Nikita Bobko

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

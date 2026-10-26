// Common includes needed by shared helpers in both WASM and FFI paths.
#include "rive/text/font_hb.hpp"
#include <stdint.h>
#include <string.h>
#include <vector>

// ── Shared color layer serialization ─────────────────────────────────────
static size_t colorLayerBufferSize(
    const std::vector<rive::Font::ColorGlyphLayer>& layers)
{
    size_t totalSize = sizeof(uint32_t); // layerCount
    for (const auto& layer : layers)
    {
        if (layer.paintType == rive::Font::ColorGlyphPaintType::image)
        {
            // Image layer: paintType + 3-byte alignment + imageWidth +
            // imageHeight +
            //   4 floats (bearingX/Y, extentX/Y) + imageByteLength + bytes
            // The 3-byte alignment accounts for the padding
            // writeColorLayerBuffer inserts after the 1-byte paintType to align
            // the next field to 4 bytes.
            size_t layerSize = sizeof(uint8_t) + // paintType
                               3 + // alignment padding after paintType
                               sizeof(uint32_t) +       // imageWidth
                               sizeof(uint32_t) +       // imageHeight
                               4 * sizeof(float) +      // bearing/extent
                               sizeof(uint32_t) +       // imageByteLength
                               layer.imageBytes.size(); // image data
            layerSize = (layerSize + 3) & ~3;           // pad to 4
            totalSize += layerSize;
        }
        else
        {
            size_t verbCount = layer.path.verbs().size();
            size_t pointCount = layer.path.points().size();
            size_t layerSize = sizeof(uint8_t) +                // paintType
                               sizeof(uint8_t) +                // useForeground
                               sizeof(uint16_t) +               // stopCount
                               sizeof(uint32_t) +               // color
                               sizeof(uint16_t) +               // verbCount
                               sizeof(uint16_t) +               // pointCount
                               pointCount * 2 * sizeof(float) + // points
                               verbCount;                       // verbs
            layerSize = (layerSize + 3) & ~3;                   // pad to 4
            if (!layer.stops.empty())
            {
                layerSize += layer.stops.size() * sizeof(float);    // offsets
                layerSize += layer.stops.size() * sizeof(uint32_t); // colors
                layerSize += 8 * sizeof(float); // gradientParams
            }
            totalSize += layerSize;
        }
    }
    return totalSize;
}

static uint8_t* writeColorLayerBuffer(
    const std::vector<rive::Font::ColorGlyphLayer>& layers,
    uint8_t* ptr)
{
    *reinterpret_cast<uint32_t*>(ptr) = (uint32_t)layers.size();
    ptr += sizeof(uint32_t);

    for (const auto& layer : layers)
    {
        *ptr++ = (uint8_t)layer.paintType;

        if (layer.paintType == rive::Font::ColorGlyphPaintType::image)
        {
            // Image layer serialization.
            while ((uintptr_t)ptr & 3)
                *ptr++ = 0; // align to 4
            *reinterpret_cast<uint32_t*>(ptr) = layer.imageWidth;
            ptr += sizeof(uint32_t);
            *reinterpret_cast<uint32_t*>(ptr) = layer.imageHeight;
            ptr += sizeof(uint32_t);
            *reinterpret_cast<float*>(ptr) = layer.imageBearingX;
            ptr += sizeof(float);
            *reinterpret_cast<float*>(ptr) = layer.imageBearingY;
            ptr += sizeof(float);
            *reinterpret_cast<float*>(ptr) = layer.imageExtentX;
            ptr += sizeof(float);
            *reinterpret_cast<float*>(ptr) = layer.imageExtentY;
            ptr += sizeof(float);
            *reinterpret_cast<uint32_t*>(ptr) =
                (uint32_t)layer.imageBytes.size();
            ptr += sizeof(uint32_t);
            memcpy(ptr, layer.imageBytes.data(), layer.imageBytes.size());
            ptr += layer.imageBytes.size();
            while ((uintptr_t)ptr & 3)
                *ptr++ = 0; // pad to 4
        }
        else
        {
            auto verbs = layer.path.verbs();
            auto points = layer.path.points();

            *ptr++ = layer.useForeground ? 1 : 0;
            *reinterpret_cast<uint16_t*>(ptr) = (uint16_t)layer.stops.size();
            ptr += sizeof(uint16_t);

            *reinterpret_cast<uint32_t*>(ptr) = layer.color;
            ptr += sizeof(uint32_t);

            *reinterpret_cast<uint16_t*>(ptr) = (uint16_t)verbs.size();
            ptr += sizeof(uint16_t);
            *reinterpret_cast<uint16_t*>(ptr) = (uint16_t)points.size();
            ptr += sizeof(uint16_t);

            size_t pointsBytes = points.size() * sizeof(rive::Vec2D);
            memcpy(ptr, points.data(), pointsBytes);
            ptr += pointsBytes;

            memcpy(ptr, verbs.data(), verbs.size());
            ptr += verbs.size();

            while ((uintptr_t)ptr & 3)
                *ptr++ = 0; // pad to 4

            if (!layer.stops.empty())
            {
                for (const auto& stop : layer.stops)
                {
                    *reinterpret_cast<float*>(ptr) = stop.offset;
                    ptr += sizeof(float);
                }
                for (const auto& stop : layer.stops)
                {
                    *reinterpret_cast<uint32_t*>(ptr) = stop.color;
                    ptr += sizeof(uint32_t);
                }
                float params[8] = {layer.x0,
                                   layer.y0,
                                   layer.x1,
                                   layer.y1,
                                   layer.r0,
                                   layer.r1,
                                   layer.startAngle,
                                   layer.endAngle};
                memcpy(ptr, params, sizeof(params));
                ptr += sizeof(params);
            }
        }
    }
    return ptr;
}
// ─────────────────────────────────────────────────────────────────────────

#ifdef __EMSCRIPTEN__

#include <emscripten.h>
#include <emscripten/bind.h>
#include <emscripten/val.h>
#include <stdint.h>
#include <stdio.h>
#include <string>

using namespace emscripten;

using WasmPtr = uint32_t;

WasmPtr makeFont(emscripten::val byteArray)
{
    std::vector<unsigned char> bytes;

    const auto l = byteArray["byteLength"].as<unsigned>();
    bytes.resize(l);

    emscripten::val memoryView{emscripten::typed_memory_view(l, bytes.data())};
    memoryView.call<void>("set", byteArray);
    auto result = HBFont::Decode(bytes);
    if (result)
    {
        return (WasmPtr)result.release();
    }
    return (WasmPtr) nullptr;
}

void deleteFont(WasmPtr font) { reinterpret_cast<HBFont*>(font)->unref(); }

uint16_t fontAxisCount(WasmPtr ptr)
{
    HBFont* font = reinterpret_cast<HBFont*>(ptr);
    return (uint16_t)font->getAxisCount();
}

rive::Font::Axis fontAxis(WasmPtr ptr, uint16_t index)
{
    HBFont* font = reinterpret_cast<HBFont*>(ptr);
    return font->getAxis(index);
}

float fontAxisValue(WasmPtr ptr, uint32_t axisTag)
{
    HBFont* font = reinterpret_cast<HBFont*>(ptr);
    return font->getAxisValue(axisTag);
}

struct GlyphPath
{
    WasmPtr rawPath;
    WasmPtr points;
    WasmPtr verbs;
    uint16_t verbCount;
};

GlyphPath makeGlyphPath(WasmPtr fontPtr, rive::GlyphID id)
{
    auto font = reinterpret_cast<HBFont*>(fontPtr);
    rive::RawPath* path = nullptr;

    const rive::RawPath& glyphRawPath = font->getPath(id);
    if (glyphRawPath.computeCoarseArea() >= 0)
    {
        path = new rive::RawPath(glyphRawPath);
    }
    else
    {
        rive::RawPath scratchPath;
        scratchPath.addPathBackwards(glyphRawPath);
        path = new rive::RawPath(scratchPath);
    }

    return {
        .rawPath = (WasmPtr)path,
        .points = (WasmPtr)path->points().data(),
        .verbs = (WasmPtr)path->verbs().data(),
        .verbCount = (uint16_t)path->verbs().size(),
    };
}

void deleteGlyphPath(WasmPtr rawPath)
{
    delete reinterpret_cast<rive::RawPath*>(rawPath);
}

void deleteShapeResult(WasmPtr shaperResult)
{
    delete reinterpret_cast<rive::SimpleArray<rive::Paragraph>*>(shaperResult);
}

WasmPtr breakLines(WasmPtr paragraphsPtr,
                   float width,
                   uint8_t align,
                   uint8_t wrap)
{
    bool autoWidth = width == -1.0f;
    auto paragraphs =
        reinterpret_cast<rive::SimpleArray<rive::Paragraph>*>(paragraphsPtr);
    float paragraphWidth = width;

    rive::SimpleArrayBuilder<uint16_t> paragraphLines;

    rive::SimpleArray<rive::SimpleArray<rive::GlyphLine>>* lines =
        new rive::SimpleArray<rive::SimpleArray<rive::GlyphLine>>(
            paragraphs->size());
    rive::SimpleArray<rive::SimpleArray<rive::GlyphLine>>& linesRef = *lines;
    size_t paragraphIndex = 0;
    for (auto& para : *paragraphs)
    {
        linesRef[paragraphIndex] = rive::GlyphLine::BreakLines(
            para.runs,
            (autoWidth || (rive::TextWrap)wrap == rive::TextWrap::noWrap)
                ? -1.0f
                : width);
        if (autoWidth)
        {
            paragraphWidth = std::max(
                paragraphWidth,
                rive::GlyphLine::ComputeMaxWidth(linesRef[paragraphIndex],
                                                 para.runs));
        }
        paragraphIndex++;
    }
    paragraphIndex = 0;
    for (auto& para : *paragraphs)
    {
        rive::GlyphLine::ComputeLineSpacing(paragraphIndex == 0,
                                            linesRef[paragraphIndex],
                                            para.runs,
                                            paragraphWidth,
                                            (rive::TextAlign)align);
        paragraphIndex++;
    }
    return (WasmPtr)lines;
}

void deleteLines(WasmPtr lines)
{
    delete reinterpret_cast<
        rive::SimpleArray<rive::SimpleArray<rive::GlyphLine>>*>(lines);
}

WasmPtr fontFeatures(WasmPtr fontPtr)
{
    auto font = reinterpret_cast<HBFont*>(fontPtr);
    if (font == nullptr)
    {
        return (WasmPtr) nullptr;
    }

    return (WasmPtr) new rive::SimpleArray<uint32_t>(font->features());
}

float fontAscent(WasmPtr fontPtr)
{
    auto font = reinterpret_cast<HBFont*>(fontPtr);
    if (font == nullptr)
    {
        return 0.0f;
    }
    return font->lineMetrics().ascent;
}

float fontDescent(WasmPtr fontPtr)
{
    auto font = reinterpret_cast<HBFont*>(fontPtr);
    if (font == nullptr)
    {
        return 0.0f;
    }
    return font->lineMetrics().descent;
}

float fontCapHeight(WasmPtr fontPtr)
{
    auto font = reinterpret_cast<HBFont*>(fontPtr);
    if (font == nullptr)
    {
        return 0.0f;
    }
    return font->lineMetrics().capHeight;
}

float fontXHeight(WasmPtr fontPtr)
{
    auto font = reinterpret_cast<HBFont*>(fontPtr);
    if (font == nullptr)
    {
        return 0.0f;
    }
    return font->lineMetrics().xHeight;
}

float convertStringToNumber(WasmPtr strPtr)
{
    auto str = reinterpret_cast<char*>(strPtr);
    errno = 0; // Clear errno before the call
    float v = std::atof(str);
    if (errno == 0)
    {
        return v;
    }
    return 0.0f;
}

float convertIntToNumber(int val) { return static_cast<float>(val); }

void deleteFontFeatures(WasmPtr features)
{
    delete reinterpret_cast<rive::SimpleArray<uint32_t>*>(features);
}

void disableFallbackFonts() { rive::Font::gFallbackProcEnabled = false; }

void enableFallbackFonts() { rive::Font::gFallbackProcEnabled = true; }

std::vector<rive::Font*> fallbackFonts;

void setFallbackFonts(emscripten::val fontsList)
{
    std::vector<int> fonts(fontsList["length"].as<unsigned>());
    {
        emscripten::val memoryView{
            emscripten::typed_memory_view(fonts.size(), fonts.data())};
        memoryView.call<void>("set", fontsList);
    }

    fallbackFonts = std::vector<rive::Font*>();
    for (auto fontPtr : fonts)
    {
        fallbackFonts.push_back(reinterpret_cast<rive::Font*>(fontPtr));
    }
}

static rive::rcp<rive::Font> pickFallbackFont(const rive::Unichar missing,
                                              const uint32_t fallbackIndex,
                                              const rive::Font*)
{
    if (fallbackIndex > 0)
    {
        return nullptr;
    }
    size_t length = fallbackFonts.size();
    for (size_t i = 0; i < length; i++)
    {
        HBFont* font = static_cast<HBFont*>(fallbackFonts[i]);
        if (font->hasGlyph(missing))
        {
            rive::rcp<rive::Font> rcFont = rive::rcp<rive::Font>(font);
            // because the font was released at load time, we need to give it an
            // extra ref whenever we bump it to a reference counted pointer.
            rcFont->ref();
            return rcFont;
        }
    }
    return nullptr;
}

WasmPtr shapeText(emscripten::val codeUnits,
                  emscripten::val runsList,
                  int defaultLevel)
{
    std::vector<uint8_t> runsBytes(runsList["byteLength"].as<unsigned>());
    {
        emscripten::val memoryView{
            emscripten::typed_memory_view(runsBytes.size(), runsBytes.data())};
        memoryView.call<void>("set", runsList);
    }
    std::vector<uint32_t> codeUnitArray(codeUnits["length"].as<unsigned>());
    {
        emscripten::val memoryView{
            emscripten::typed_memory_view(codeUnitArray.size(),
                                          codeUnitArray.data())};
        memoryView.call<void>("set", codeUnits);
    }

    auto runCount = runsBytes.size() / sizeof(rive::TextRun);
    rive::TextRun* runs = reinterpret_cast<rive::TextRun*>(runsBytes.data());

    if (runCount > 0)
    {
        auto result = (WasmPtr) new rive::SimpleArray<rive::Paragraph>(
            runs[0].font->shapeText(codeUnitArray,
                                    rive::Span<rive::TextRun>(runs, runCount),
                                    defaultLevel));
        return result;
    }
    return {};
}

WasmPtr makeFontWithOptions(WasmPtr fontPtr,
                            emscripten::val coordsList,
                            emscripten::val featuresList)
{
    std::vector<uint8_t> coordsBytes(coordsList["byteLength"].as<unsigned>());
    {
        emscripten::val memoryView{
            emscripten::typed_memory_view(coordsBytes.size(),
                                          coordsBytes.data())};
        memoryView.call<void>("set", coordsList);
    }
    auto coordsCount = coordsBytes.size() / sizeof(rive::Font::Coord);
    rive::Font::Coord* coords =
        reinterpret_cast<rive::Font::Coord*>(coordsBytes.data());

    std::vector<uint8_t> featuresBytes(
        featuresList["byteLength"].as<unsigned>());
    {
        emscripten::val memoryView{
            emscripten::typed_memory_view(featuresBytes.size(),
                                          featuresBytes.data())};
        memoryView.call<void>("set", featuresList);
    }
    auto featuresCount = featuresBytes.size() / sizeof(rive::Font::Feature);
    rive::Font::Feature* features =
        reinterpret_cast<rive::Font::Feature*>(featuresBytes.data());

    HBFont* font = reinterpret_cast<HBFont*>(fontPtr);
    auto variableFont = font->withOptions(
        rive::Span<rive::Font::Coord>(coords, coordsCount),
        rive::Span<rive::Font::Feature>(features, featuresCount));
    if (variableFont != nullptr)
    {
        return (WasmPtr)variableFont.release();
    }
    return (WasmPtr) nullptr;
}

void init()
{
    fallbackFonts.clear();
    rive::Font::gFallbackProc = pickFallbackFont;
}

// Color glyph (emoji) support - WASM versions.

bool wasmFontHasColorGlyphs(WasmPtr fontPtr)
{
    auto font = reinterpret_cast<HBFont*>(fontPtr);
    if (font == nullptr)
    {
        return false;
    }
    return font->hasColorGlyphs();
}

bool wasmFontIsColorGlyph(WasmPtr fontPtr, rive::GlyphID glyphId)
{
    auto font = reinterpret_cast<HBFont*>(fontPtr);
    if (font == nullptr)
    {
        return false;
    }
    return font->isColorGlyph(glyphId);
}

// Returns a serialized binary buffer with all color glyph layers.
// Format:
//   uint32 layerCount
//   per layer:
//     uint8  paintType (0=solid, 1=linear, 2=radial, 3=sweep)
//     uint8  useForeground
//     uint16 stopCount
//     uint32 color
//     uint16 verbCount
//     uint16 pointCount
//     float[pointCount*2] points (x,y pairs)
//     uint8[verbCount] verbs
//     (padding to 4-byte alignment)
//     if stopCount > 0:
//       float[stopCount] offsets
//       uint32[stopCount] colors
//       float[8] gradientParams (x0,y0,x1,y1,r0,r1,startAngle,endAngle)
// Returns a WasmPtr to the buffer and writes the size to *outSize.
// Caller frees with wasmDeleteColorGlyphBuffer.
WasmPtr wasmGetColorGlyphLayers(WasmPtr fontPtr,
                                rive::GlyphID glyphId,
                                uint32_t foregroundColor,
                                WasmPtr outSizePtr)
{
    auto* outSize = reinterpret_cast<uint32_t*>(outSizePtr);
    auto font = reinterpret_cast<HBFont*>(fontPtr);
    if (font == nullptr || outSize == nullptr)
    {
        if (outSize)
            *outSize = 0;
        return 0;
    }
    std::vector<rive::Font::ColorGlyphLayer> layers;
    size_t count =
        font->getColorLayers(glyphId, layers, (rive::ColorInt)foregroundColor);
    if (count == 0)
    {
        *outSize = 0;
        return 0;
    }

    size_t totalSize = colorLayerBufferSize(layers);
    auto* buffer = new uint8_t[totalSize];
    uint8_t* end = writeColorLayerBuffer(layers, buffer);

    *outSize = (uint32_t)(end - buffer);
    return (WasmPtr)buffer;
}

void wasmDeleteColorGlyphBuffer(WasmPtr ptr)
{
    if (ptr == 0)
    {
        return;
    }
    delete[] reinterpret_cast<uint8_t*>(ptr);
}

#ifdef DEBUG
// clang-format off
#define OFFSET_OF(type, member) ((int)(intptr_t)&(((type*)(void*)0)->member))
// clang-format on
void assertSomeAssumptions()
{
    // These assumptions are important as our rive_text_wasm.dart integration
    // relies on knowing the exact offsets of these struct elements. When and if
    // we ever move to the proposed Wasm64 (currently not a standard), we'll
    // need to make adjustements here.
    assert(sizeof(rive::TextRun) == 28);
    assert(OFFSET_OF(rive::TextRun, font) == 0);
    assert(OFFSET_OF(rive::TextRun, size) == 4);
    assert(OFFSET_OF(rive::TextRun, lineHeight) == 8);
    assert(OFFSET_OF(rive::TextRun, letterSpacing) == 12);
    assert(OFFSET_OF(rive::TextRun, unicharCount) == 16);
    assert(OFFSET_OF(rive::TextRun, script) == 20);
    assert(OFFSET_OF(rive::TextRun, styleId) == 24);
    assert(OFFSET_OF(rive::TextRun, level) == 26);

    assert(sizeof(rive::Paragraph) == 12);
    assert(OFFSET_OF(rive::Paragraph, runs) == 0);
    assert(OFFSET_OF(rive::Paragraph, level) == 8);

    assert(sizeof(rive::GlyphRun) == 76);
    assert(OFFSET_OF(rive::GlyphRun, font) == 0);
    assert(OFFSET_OF(rive::GlyphRun, size) == 4);
    assert(OFFSET_OF(rive::GlyphRun, lineHeight) == 8);
    assert(OFFSET_OF(rive::GlyphRun, letterSpacing) == 12);
    assert(OFFSET_OF(rive::GlyphRun, glyphs) == 16);
    assert(OFFSET_OF(rive::GlyphRun, textIndices) == 24);
    assert(OFFSET_OF(rive::GlyphRun, advances) == 32);
    assert(OFFSET_OF(rive::GlyphRun, xpos) == 40);
    assert(OFFSET_OF(rive::GlyphRun, offsets) == 48);
    assert(OFFSET_OF(rive::GlyphRun, breaks) == 56);
    assert(OFFSET_OF(rive::GlyphRun, styleId) == 64);
    assert(OFFSET_OF(rive::GlyphRun, level) == 66);
    assert(OFFSET_OF(rive::GlyphRun, joiners) == 68);

    assert(sizeof(rive::GlyphLine) == 32);
}
#endif

EMSCRIPTEN_BINDINGS(RiveText)
{
    function("makeFont", &makeFont, allow_raw_pointers());
    function("deleteFont", &deleteFont);

    value_array<rive::Font::Axis>("FontAxis")
        .element(&rive::Font::Axis::tag)
        .element(&rive::Font::Axis::min)
        .element(&rive::Font::Axis::def)
        .element(&rive::Font::Axis::max);

    value_array<GlyphPath>("GlyphPath")
        .element(&GlyphPath::rawPath)
        .element(&GlyphPath::points)
        .element(&GlyphPath::verbs)
        .element(&GlyphPath::verbCount);

    function("fontAxisCount", &fontAxisCount);
    function("fontAxis", &fontAxis);
    function("fontAxisValue", &fontAxisValue);
    function("makeFontWithOptions", &makeFontWithOptions);
    function("fontFeatures", &fontFeatures);
    function("deleteFontFeatures", &deleteFontFeatures);
    function("disableFallbackFonts", &disableFallbackFonts);
    function("enableFallbackFonts", &enableFallbackFonts);

    function("fontAscent", &fontAscent);
    function("fontDescent", &fontDescent);
    function("fontCapHeight", &fontCapHeight);
    function("fontXHeight", &fontXHeight);
    function("convertStringToNumber", &convertStringToNumber);
    function("convertIntToNumber", &convertIntToNumber);

    function("makeGlyphPath", &makeGlyphPath);
    function("deleteGlyphPath", &deleteGlyphPath);

    function("shapeText", &shapeText);
    function("setFallbackFonts", &setFallbackFonts);
    function("deleteShapeResult", &deleteShapeResult);

    function("breakLines", &breakLines);
    function("deleteLines", &deleteLines);
    function("init", &init);

    function("fontHasColorGlyphs", &wasmFontHasColorGlyphs);
    function("fontIsColorGlyph", &wasmFontIsColorGlyph);
    function("getColorGlyphLayers", &wasmGetColorGlyphLayers);
    function("deleteColorGlyphBuffer", &wasmDeleteColorGlyphBuffer);

#ifdef DEBUG
    function("assertSomeAssumptions", &assertSomeAssumptions);
#endif
}
#else
#include <stdint.h>
#include <stdio.h>

#include "rive_native/external.hpp"
#include "rive/text/font_hb.hpp"

EXPORT
rive::Font* makeFont(const uint8_t* bytes, uint64_t length)
{
    if (bytes == nullptr)
    {
        return nullptr;
    }
    auto result = HBFont::Decode(rive::Span<const uint8_t>(bytes, length));
    if (result)
    {
        auto ptr = result.release();
        return ptr;
    }
    return nullptr;
}

EXPORT void riveFontDummyLinker()
{
    // Force including for Linux.
}

EXPORT void deleteFont(rive::Font* font)
{
    if (font != nullptr)
    {
        font->unref();
    }
}

struct GlyphPath
{
    rive::RawPath* rawPath;
    rive::Vec2D* points;
    rive::PathVerb* verbs;
    uint16_t verbCount;
};

EXPORT
GlyphPath makeGlyphPath(rive::Font* font, rive::GlyphID id)
{
    rive::RawPath* path = nullptr;

    const rive::RawPath& glyphRawPath = font->getPath(id);
    if (glyphRawPath.computeCoarseArea() >= 0)
    {
        path = new rive::RawPath(glyphRawPath);
    }
    else
    {
        rive::RawPath scratchPath;
        scratchPath.addPathBackwards(glyphRawPath);
        path = new rive::RawPath(scratchPath);
    }

    return {
        .rawPath = path,
        .points = path->points().data(),
        .verbs = path->verbs().data(),
        .verbCount = (uint16_t)path->verbs().size(),
    };
}

EXPORT void deleteGlyphPath(rive::RawPath* rawPath) { delete rawPath; }

EXPORT
uint16_t fontAxisCount(rive::Font* font)
{
    return (uint16_t)font->getAxisCount();
}

EXPORT
HBFont::Axis fontAxis(rive::Font* font, uint16_t index)
{
    return font->getAxis(index);
}

EXPORT
float fontAxisValue(rive::Font* font, uint32_t axisTag)
{
    return font->getAxisValue(axisTag);
}

EXPORT
float fontAscent(rive::Font* font) { return font->lineMetrics().ascent; }

EXPORT
float fontDescent(rive::Font* font) { return font->lineMetrics().descent; }

EXPORT
float fontCapHeight(rive::Font* font) { return font->lineMetrics().capHeight; }

EXPORT
float fontXHeight(rive::Font* font) { return font->lineMetrics().xHeight; }

EXPORT
float convertStringToNumber(char* str)
{

    errno = 0; // Clear errno before the call
    float v = std::atof(str);
    if (errno == 0)
    {
        return v;
    }
    return 0.0f;
}

EXPORT
float convertIntToNumber(int value) { return static_cast<float>(value); }

EXPORT
rive::Font* makeFontWithOptions(rive::Font* font,
                                rive::Font::Coord* coords,
                                uint64_t coordsLength,
                                rive::Font::Feature* features,
                                uint64_t featureLength)
{
    auto result = font->withOptions(
        rive::Span<rive::Font::Coord>(coords, coordsLength),
        rive::Span<rive::Font::Feature>(features, featureLength));
    if (result)
    {
        auto ptr = result.release();
        return ptr;
    }
    return nullptr;
}

EXPORT
rive::SimpleArray<rive::Paragraph>* shapeText(const uint32_t* text,
                                              uint64_t length,
                                              rive::TextRun* runs,
                                              uint64_t runsLength,
                                              int defaultLevel)
{
    if (runsLength == 0 || length == 0)
    {
        return nullptr;
    }
    return new rive::SimpleArray<rive::Paragraph>(
        runs[0].font->shapeText(rive::Span<const uint32_t>(text, length),
                                rive::Span<rive::TextRun>(runs, runsLength),
                                defaultLevel));
}

EXPORT void deleteShapeResult(rive::SimpleArray<rive::Paragraph>* shapeResult)
{
    delete shapeResult;
}

EXPORT rive::SimpleArray<rive::SimpleArray<rive::GlyphLine>>* breakLines(
    rive::SimpleArray<rive::Paragraph>* paragraphs,
    float width,
    uint8_t align,
    uint8_t wrap)
{
    bool autoWidth = width == -1.0f;
    float paragraphWidth = width;

    rive::SimpleArray<rive::SimpleArray<rive::GlyphLine>>* lines =
        new rive::SimpleArray<rive::SimpleArray<rive::GlyphLine>>(
            paragraphs->size());
    rive::SimpleArray<rive::SimpleArray<rive::GlyphLine>>& linesRef = *lines;
    size_t paragraphIndex = 0;
    for (auto& para : *paragraphs)
    {
        linesRef[paragraphIndex] = rive::GlyphLine::BreakLines(
            para.runs,
            (autoWidth || (rive::TextWrap)wrap == rive::TextWrap::noWrap)
                ? -1.0f
                : width);
        if (autoWidth)
        {
            paragraphWidth = std::max(
                paragraphWidth,
                rive::GlyphLine::ComputeMaxWidth(linesRef[paragraphIndex],
                                                 para.runs));
        }
        paragraphIndex++;
    }
    paragraphIndex = 0;
    for (auto& para : *paragraphs)
    {
        rive::GlyphLine::ComputeLineSpacing(paragraphIndex == 0,
                                            linesRef[paragraphIndex],
                                            para.runs,
                                            paragraphWidth,
                                            (rive::TextAlign)align);
        paragraphIndex++;
    }
    return lines;
}

EXPORT void deleteLines(
    rive::SimpleArray<rive::SimpleArray<rive::GlyphLine>>* result)
{
    delete result;
}

std::vector<rive::Font*> fallbackFonts;
bool useFallbackFonts = false;

EXPORT
void setFallbackFonts(rive::Font** fonts, uint64_t fontsLength)
{
    if (fontsLength == 0)
    {
        fallbackFonts = std::vector<rive::Font*>();
        return;
    }
    fallbackFonts = std::vector<rive::Font*>(fonts, fonts + fontsLength);
}

static rive::rcp<rive::Font> pickFallbackFont(const rive::Unichar missing,
                                              const uint32_t fallbackIndex,
                                              const rive::Font*)
{
    if (fallbackIndex > 1)
    {
        return nullptr;
    }
    size_t length = fallbackFonts.size();
    for (size_t i = 0; i < length; i++)
    {
        HBFont* font = static_cast<HBFont*>(fallbackFonts[i]);
        if (font->hasGlyph(missing))
        {
            rive::rcp<rive::Font> rcFont = rive::rcp<rive::Font>(font);
            // because the font was released at load time, we need to give it an
            // extra ref whenever we bump it to a reference counted pointer.
            rcFont->ref();
            return rcFont;
        }
    }
    return nullptr;
}

EXPORT
void init()
{
    fallbackFonts.clear();
    rive::Font::gFallbackProc = pickFallbackFont;
}

EXPORT
rive::SimpleArray<uint32_t>* fontFeatures(rive::Font* font)
{
    if (font == nullptr)
    {
        return nullptr;
    }

    return new rive::SimpleArray<uint32_t>(font->features());
}

EXPORT void deleteFontFeatures(rive::SimpleArray<uint32_t>* features)
{
    delete features;
}

// Color glyph (emoji) support.

EXPORT bool fontHasColorGlyphs(rive::Font* font)
{
    if (font == nullptr)
    {
        return false;
    }
    return font->hasColorGlyphs();
}

EXPORT bool fontIsColorGlyph(rive::Font* font, rive::GlyphID glyphId)
{
    if (font == nullptr)
    {
        return false;
    }
    return font->isColorGlyph(glyphId);
}

// Serializes all color glyph layers into a flat binary buffer.
// Uses the shared colorLayerBufferSize/writeColorLayerBuffer format.
// Returns the buffer pointer and writes the size to *outSize.
// Caller frees with deleteColorGlyphBuffer.
EXPORT uint8_t* fontGetColorGlyphLayers(rive::Font* font,
                                        rive::GlyphID glyphId,
                                        uint32_t foregroundColor,
                                        uint32_t* outSize)
{
    if (font == nullptr || outSize == nullptr)
    {
        if (outSize)
            *outSize = 0;
        return nullptr;
    }

    std::vector<rive::Font::ColorGlyphLayer> layers;
    size_t count =
        font->getColorLayers(glyphId, layers, (rive::ColorInt)foregroundColor);
    if (count == 0)
    {
        *outSize = 0;
        return nullptr;
    }

    size_t totalSize = colorLayerBufferSize(layers);
    auto* buffer = new uint8_t[totalSize];
    uint8_t* end = writeColorLayerBuffer(layers, buffer);

    *outSize = (uint32_t)(end - buffer);
    return buffer;
}

EXPORT void deleteColorGlyphBuffer(uint8_t* buffer) { delete[] buffer; }

EXPORT void disableFallbackFonts() { rive::Font::gFallbackProcEnabled = false; }

EXPORT void enableFallbackFonts() { rive::Font::gFallbackProcEnabled = true; }
#endif
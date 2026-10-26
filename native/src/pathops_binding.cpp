/*
 * Copyright 2026 Rive
 *
 * Editor-only bindings for boolean path operations (packages/pathops).
 * Never compiled into the flutter runtime (see premake filter).
 *
 * Paths cross the boundary as flat buffers: an array of verbs (matching
 * rive::PathVerb values) and an array of x,y floats consumed per-verb
 * (move=1 point, line=1, quad=2, cubic=3, close=0). Results come back as a
 * heap-allocated rive::RawPath plus views over its verb/point storage,
 * mirroring the GlyphPath pattern in text_binding.cpp.
 */

#include "rive/math/raw_path.hpp"
#include "rive/pathops/pathops.hpp"

#include <stdint.h>
#include <vector>

namespace
{
// Builds a RawPath from flat buffers. 'floatCount' bounds reads from
// 'points'; pass kFloatCountUnknown when the caller has no length (the C
// ABI carries only verbCount -- those callers are gated on the Dart side,
// which never hands a short buffer across).
static constexpr uint32_t kFloatCountUnknown = ~0u;

static rive::RawPath buildRawPath(const float* points,
                                  const uint8_t* verbs,
                                  uint32_t verbCount,
                                  uint32_t floatCount)
{
    rive::RawPath path;
    const float* p = points;
    uint32_t used = 0;
    auto has = [&](uint32_t floats) {
        if (floatCount != kFloatCountUnknown && used + floats > floatCount)
        {
            return false;
        }
        used += floats;
        return true;
    };
    for (uint32_t i = 0; i < verbCount; ++i)
    {
        switch (static_cast<rive::PathVerb>(verbs[i]))
        {
            case rive::PathVerb::move:
                if (!has(2))
                {
                    return rive::RawPath();
                }
                path.moveTo(p[0], p[1]);
                p += 2;
                break;
            case rive::PathVerb::line:
                if (!has(2))
                {
                    return rive::RawPath();
                }
                path.lineTo(p[0], p[1]);
                p += 2;
                break;
            case rive::PathVerb::quad:
                if (!has(4))
                {
                    return rive::RawPath();
                }
                path.quadTo(p[0], p[1], p[2], p[3]);
                p += 4;
                break;
            case rive::PathVerb::cubic:
                if (!has(6))
                {
                    return rive::RawPath();
                }
                path.cubicTo(p[0], p[1], p[2], p[3], p[4], p[5]);
                p += 6;
                break;
            case rive::PathVerb::close:
                path.close();
                break;
            default:
                // Fail closed on an unrecognized verb byte: without this a
                // malformed verb would skip the pointer advance and desync
                // every subsequent point read (potentially out of bounds).
                // An empty path makes the whole op a no-op downstream.
                return rive::RawPath();
        }
    }
    return path;
}
} // namespace

#ifdef __EMSCRIPTEN__

#include <emscripten.h>
#include <emscripten/bind.h>
#include <emscripten/val.h>

using namespace emscripten;

using WasmPtr = uint32_t;

struct PathOpsResult
{
    WasmPtr rawPath;
    WasmPtr points;
    WasmPtr verbs;
    uint32_t verbCount;
    uint32_t pointCount;
    uint32_t fillRule;
    uint32_t success;
};

static std::vector<float> floatsFromVal(val array)
{
    auto length = array["length"].as<unsigned>();
    std::vector<float> data(length);
    val memoryView{typed_memory_view(length, data.data())};
    memoryView.call<void>("set", array);
    return data;
}

static std::vector<uint8_t> bytesFromVal(val array)
{
    auto length = array["length"].as<unsigned>();
    std::vector<uint8_t> data(length);
    val memoryView{typed_memory_view(length, data.data())};
    memoryView.call<void>("set", array);
    return data;
}

static PathOpsResult wrapResult(rive::RawPath&& result,
                                rive::FillRule fillRule,
                                bool success)
{
    if (!success)
    {
        return {0, 0, 0, 0, 0, 0, 0};
    }
    rive::RawPath* path = new rive::RawPath(std::move(result));
    return {
        (WasmPtr)path,
        (WasmPtr)path->points().data(),
        (WasmPtr)path->verbs().data(),
        (uint32_t)path->verbs().size(),
        (uint32_t)path->points().size(),
        (uint32_t)fillRule,
        1u,
    };
}

static PathOpsResult combinePaths(uint32_t pathOp,
                                  val pointsA,
                                  val verbsA,
                                  uint32_t fillRuleA,
                                  val pointsB,
                                  val verbsB,
                                  uint32_t fillRuleB)
{
    std::vector<float> ptsA = floatsFromVal(pointsA);
    std::vector<uint8_t> vbsA = bytesFromVal(verbsA);
    std::vector<float> ptsB = floatsFromVal(pointsB);
    std::vector<uint8_t> vbsB = bytesFromVal(verbsB);

    rive::RawPath a = buildRawPath(ptsA.data(),
                                   vbsA.data(),
                                   (uint32_t)vbsA.size(),
                                   (uint32_t)ptsA.size());
    rive::RawPath b = buildRawPath(ptsB.data(),
                                   vbsB.data(),
                                   (uint32_t)vbsB.size(),
                                   (uint32_t)ptsB.size());

    rive::RawPath result;
    rive::FillRule resultFillRule = rive::FillRule::nonZero;
    bool success = rive::CombinePaths(static_cast<rive::PathOp>(pathOp),
                                      a,
                                      static_cast<rive::FillRule>(fillRuleA),
                                      b,
                                      static_cast<rive::FillRule>(fillRuleB),
                                      &result,
                                      &resultFillRule);
    return wrapResult(std::move(result), resultFillRule, success);
}

static PathOpsResult simplifyPath(val points, val verbs, uint32_t fillRule)
{
    std::vector<float> pts = floatsFromVal(points);
    std::vector<uint8_t> vbs = bytesFromVal(verbs);

    rive::RawPath path = buildRawPath(pts.data(),
                                      vbs.data(),
                                      (uint32_t)vbs.size(),
                                      (uint32_t)pts.size());

    rive::RawPath result;
    rive::FillRule resultFillRule = rive::FillRule::nonZero;
    bool success = rive::SimplifyPath(path,
                                      static_cast<rive::FillRule>(fillRule),
                                      &result,
                                      &resultFillRule);
    return wrapResult(std::move(result), resultFillRule, success);
}

static void deletePathOpsResult(WasmPtr rawPath)
{
    delete reinterpret_cast<rive::RawPath*>(rawPath);
}

EMSCRIPTEN_BINDINGS(RivePathOps)
{
    value_array<PathOpsResult>("PathOpsResult")
        .element(&PathOpsResult::rawPath)
        .element(&PathOpsResult::points)
        .element(&PathOpsResult::verbs)
        .element(&PathOpsResult::verbCount)
        .element(&PathOpsResult::pointCount)
        .element(&PathOpsResult::fillRule)
        .element(&PathOpsResult::success);

    function("combinePaths", &combinePaths);
    function("simplifyPath", &simplifyPath);
    function("deletePathOpsResult", &deletePathOpsResult);
}

#else

#include "rive_native/external.hpp"

struct PathOpsResult
{
    rive::RawPath* rawPath;
    const rive::Vec2D* points;
    const uint8_t* verbs;
    uint32_t verbCount;
    uint32_t pointCount;
    uint32_t fillRule;
    uint32_t success;
};

static PathOpsResult wrapResult(rive::RawPath&& result,
                                rive::FillRule fillRule,
                                bool success)
{
    if (!success)
    {
        return {nullptr, nullptr, nullptr, 0, 0, 0, 0};
    }
    rive::RawPath* path = new rive::RawPath(std::move(result));
    return {
        path,
        path->points().data(),
        reinterpret_cast<const uint8_t*>(path->verbs().data()),
        (uint32_t)path->verbs().size(),
        (uint32_t)path->points().size(),
        (uint32_t)fillRule,
        1u,
    };
}

EXPORT
PathOpsResult combinePaths(uint32_t pathOp,
                           const float* pointsA,
                           const uint8_t* verbsA,
                           uint32_t verbCountA,
                           uint32_t fillRuleA,
                           const float* pointsB,
                           const uint8_t* verbsB,
                           uint32_t verbCountB,
                           uint32_t fillRuleB)
{
    rive::RawPath a =
        buildRawPath(pointsA, verbsA, verbCountA, kFloatCountUnknown);
    rive::RawPath b =
        buildRawPath(pointsB, verbsB, verbCountB, kFloatCountUnknown);

    rive::RawPath result;
    rive::FillRule resultFillRule = rive::FillRule::nonZero;
    bool success = rive::CombinePaths(static_cast<rive::PathOp>(pathOp),
                                      a,
                                      static_cast<rive::FillRule>(fillRuleA),
                                      b,
                                      static_cast<rive::FillRule>(fillRuleB),
                                      &result,
                                      &resultFillRule);
    return wrapResult(std::move(result), resultFillRule, success);
}

EXPORT
PathOpsResult simplifyPath(const float* points,
                           const uint8_t* verbs,
                           uint32_t verbCount,
                           uint32_t fillRule)
{
    rive::RawPath path =
        buildRawPath(points, verbs, verbCount, kFloatCountUnknown);

    rive::RawPath result;
    rive::FillRule resultFillRule = rive::FillRule::nonZero;
    bool success = rive::SimplifyPath(path,
                                      static_cast<rive::FillRule>(fillRule),
                                      &result,
                                      &resultFillRule);
    return wrapResult(std::move(result), resultFillRule, success);
}

EXPORT void deletePathOpsResult(rive::RawPath* rawPath) { delete rawPath; }

#endif

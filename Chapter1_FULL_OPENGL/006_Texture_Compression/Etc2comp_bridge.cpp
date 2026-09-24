#include "etc2comp_bridge.h"

#include "etc2comp/EtcLib/Etc/Etc.h"
#include "etc2comp/EtcLib/Etc/EtcImage.h"
#include "etc2comp/EtcLib/Etc/EtcFilter.h"
#include "etc2comp/EtcTool/EtcFile.h"

#define STB_IMAGE_IMPLEMENTATION
#include <stb/stb_image.h>

#include <vector>
#include <thread>

extern "C" int etc2_convert_to_ktx(const char* jpgPath, const char* ktxPath)
{
 
    int w, h, sourceComp;
    const uint8_t* img = stbi_load(jpgPath, &w, &h, &sourceComp, 4);
    if (!img)
    {
      
        return 1;
    }


    std::vector<float> rgbaf;
    rgbaf.reserve(static_cast<size_t>(w) * h * 4);
    for (int i = 0; i != w * h * 4; i += 4)
    {
        rgbaf.push_back(img[i + 0] / 255.0f);
        rgbaf.push_back(img[i + 1] / 255.0f);
        rgbaf.push_back(img[i + 2] / 255.0f);
        rgbaf.push_back(img[i + 3] / 255.0f);
    }
    stbi_image_free(const_cast<void*>(static_cast<const void*>(img)));


    const auto etcFormat   = Etc::Image::Format::RGB8;
    const auto errorMetric = Etc::ErrorMetric::BT709;

    Etc::Image image(rgbaf.data(), w, h, errorMetric);

    image.Encode(etcFormat, errorMetric, ETCCOMP_DEFAULT_EFFORT_LEVEL,
                 std::thread::hardware_concurrency(), 1024);

    Etc::File etcFile(
        ktxPath,
        Etc::File::Format::KTX,
        etcFormat,
        image.GetEncodingBits(),
        image.GetEncodingBitsBytes(),
        image.GetSourceWidth(),
        image.GetSourceHeight(),
        image.GetExtendedWidth(),
        image.GetExtendedHeight());
    etcFile.Write();

    return 0;
}

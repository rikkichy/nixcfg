// HarfBuzz owns instancing, name serialization and sfnt checksums. Only the
// three fixed OpenType style fields below need explicit metadata adjustments.
#include <hb-subset.h>

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <vector>

static void require(bool ok, const char *message)
{
    if (!ok) {
        std::fprintf(stderr, "instance-font: %s\n", message);
        std::exit(1);
    }
}

static unsigned read16(const char *data)
{
    return (static_cast<unsigned char>(data[0]) << 8) | static_cast<unsigned char>(data[1]);
}

static void write16(char *data, unsigned value)
{
    data[0] = static_cast<char>(value >> 8);
    data[1] = static_cast<char>(value & 0xff);
}

int main(int argc, char **argv)
{
    require(argc == 3, "usage: instance-font INPUT.ttf OUTPUT.ttf");
    auto *source = hb_face_create_from_file_or_fail(argv[1], 0);
    require(source && hb_face_get_glyph_count(source), "cannot load source font");
    const auto weightTag = HB_TAG('w', 'g', 'h', 't');
    hb_ot_var_axis_info_t weight;
    require(hb_ot_var_find_axis_info(source, weightTag, &weight)
                && weight.min_value <= 600 && weight.max_value >= 600,
            "source font does not support weight 600");

    auto *input = hb_subset_input_create_or_fail();
    require(input, "cannot allocate subset input");
    hb_subset_input_keep_everything(input);
    hb_subset_input_set_flags(input, hb_subset_input_get_flags(input) | HB_SUBSET_FLAGS_RETAIN_GIDS);
    // Rounded outlines are already baked into the pinned source; all other
    // variable axes stay at their defaults, exactly as in the desktop font.
    require(hb_subset_input_pin_all_axes_to_default(input, source)
                && hb_subset_input_pin_axis_location(input, source, weightTag, 600),
            "cannot pin font axes");
    hb_set_add(hb_subset_input_set(input, HB_SUBSET_SETS_DROP_TABLE_TAG), HB_TAG('S', 'T', 'A', 'T'));
    auto *nameIds = hb_subset_input_set(input, HB_SUBSET_SETS_NAME_ID);
    hb_set_del(nameIds, 25); // No variable-font PostScript name prefix.
    const struct { unsigned id; const char *value; } names[] = {
        {1, "Google Sans Flex Rounded"}, {2, "Semibold"},
        {3, "GoogleSansFlexRounded-Semibold-600"},
        {4, "Google Sans Flex Rounded Semibold"},
        {6, "GoogleSansFlexRounded-Semibold"},
        {16, "Google Sans Flex Rounded"}, {17, "Semibold"},
        {21, "Google Sans Flex Rounded"}, {22, "Semibold"},
    };
    for (const auto &name : names) {
        // Filtering removes every old locale/platform record for these IDs.
        // HarfBuzz inserts overrides after filtering, including absent names.
        hb_set_del(nameIds, name.id);
        require(hb_subset_input_override_name_table(input, name.id, 3, 1, 0x409, name.value, -1)
                    && hb_subset_input_override_name_table(input, name.id, 1, 0, 0, name.value, -1),
                "cannot set Semibold font names");
    }
    auto *instance = hb_subset_or_fail(source, input);
    require(instance && hb_face_get_glyph_count(instance) == hb_face_get_glyph_count(source)
                && hb_ot_var_get_axis_count(instance) == 0,
            "instancing failed or lost glyphs/retained variable axes");
    hb_subset_input_destroy(input);
    hb_face_destroy(source);

    // OpenType OS/2: usWeightClass at byte 4, fsSelection at byte 62;
    // head: macStyle at byte 44. All other bytes remain HarfBuzz's output.
    constexpr auto os2Tag = HB_TAG('O', 'S', '/', '2');
    constexpr auto headTag = HB_TAG('h', 'e', 'a', 'd');
    auto *output = hb_face_builder_create();
    unsigned count = hb_face_get_table_tags(instance, 0, nullptr, nullptr);
    require(count > 0, "instance has no font tables");
    std::vector<hb_tag_t> tags(count);
    hb_face_get_table_tags(instance, 0, &count, tags.data());
    bool hasOS2 = false;
    bool hasHead = false;
    for (unsigned i = 0; i < count; ++i) {
        const auto tag = tags[i];
        require(tag != HB_TAG('f', 'v', 'a', 'r') && tag != HB_TAG('S', 'T', 'A', 'T'),
                "static font retained fvar or STAT");
        auto *table = hb_face_reference_table(instance, tag);
        if (tag == os2Tag || tag == headTag) {
            auto *copy = hb_blob_copy_writable_or_fail(table);
            hb_blob_destroy(table);
            require(copy, "cannot copy font style metadata");
            table = copy;
            unsigned length = 0;
            char *data = hb_blob_get_data_writable(table, &length);
            require(data && length >= (tag == os2Tag ? 64u : 46u), "truncated font style metadata");
            if (tag == os2Tag) {
                write16(data + 4, 600);
                write16(data + 62, read16(data + 62) & ~((1u << 5) | (1u << 6)));
                hasOS2 = true;
            } else {
                write16(data + 44, read16(data + 44) & ~1u);
                hasHead = true;
            }
        }
        require(hb_face_builder_add_table(output, tag, table), "cannot serialize font table");
        hb_blob_destroy(table);
    }
    require(hasOS2 && hasHead, "font is missing OS/2 or head metadata");
    hb_face_destroy(instance);
    for (const auto &name : names) {
        char value[128] = {};
        unsigned length = sizeof(value);
        hb_ot_name_get_utf8(output, name.id, hb_language_from_string("en", -1), &length, value);
        require(std::strcmp(value, name.value) == 0, "incorrect Semibold font name");
    }
    auto *blob = hb_face_reference_blob(output);
    unsigned length = 0;
    const char *data = hb_blob_get_data(blob, &length);
    require(data && length, "cannot serialize static font");
    std::ofstream file(argv[2], std::ios::binary);
    file.write(data, length);
    file.close();
    require(file.good(), "cannot write static font");
    hb_blob_destroy(blob);
    hb_face_destroy(output);
}

#ifndef RVG_SCENE_H
#define RVG_SCENE_H

#include "rvg-i-xformable.h"
#include "rvg-scene-data.h"
#include "rvg-rgba.h"

namespace rvg {

// This is simply an input scene that can be xformed and has a background color
class scene: public i_xformable<scene> {

    scene_data::const_ptr m_scene_ptr;

    RGBA8 m_background_color;

public:

    explicit scene(scene_data::const_ptr scene_ptr,
        RGBA8 color = RGBA8{255,255,255,255}):
        m_scene_ptr(scene_ptr),
        m_background_color{color} { ; }

    const scene_data &get_scene_data(void) const {
        return *m_scene_ptr;
    }

    scene_data::const_ptr get_scene_data_ptr(void) const {
        return m_scene_ptr;
    }

    RGBA8 get_background_color(void) const {
        return m_background_color;
    }

    void set_background_color(RGBA8 color) {
        m_background_color = color;
    }

    scene without_background_color(void) const {
        return scene{m_scene_ptr};
    }

    scene over(RGBA8 color) const {
        return scene{m_scene_ptr,
            post_divide(
                rvg::over(
                    pre_multiply(color),
                    pre_multiply(m_background_color)))};
    }

};

}

#endif

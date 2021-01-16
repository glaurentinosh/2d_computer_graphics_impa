#ifndef RVG_LUA_XFORM_H
#define RVG_LUA_XFORM_H

#include "rvg-lua.h"
#include "rvg-xform.h"

// There are many types of xform: identity, rotation, scaling, translation,
// linear, affinity, projectivity.
// They are represented by userdata with different metatables in Lua.
// We want library functions to be able to accept objects of all these types as
// if they were all a single type.
// To do so, we declare explicit specializations of function that obtain a xform
// from an entry in the stack
template <> rvg::xform rvg_lua_check<rvg::xform>(lua_State *L, int idx, int ctxidx);
template <> rvg::xform *rvg_lua_check_pointer<rvg::xform>(lua_State *L, int idx, int ctxidx);
// And we make sure no other module tries to instantiate them from the templates in
// rvg-lua.h, because their explicit specializations are defined in rvg-lua-xform.cpp
extern template rvg::xform rvg_lua_check<rvg::xform>(lua_State *L, int idx, int ctxidx);
extern template rvg::xform *rvg_lua_check_pointer<rvg::xform>(lua_State *L, int idx, int ctxidx);

int rvg_lua_xform_init(lua_State *L, int ctxidx);
int rvg_lua_xform_export(lua_State *L, int ctxidx);

rvg::xform rvg_lua_xform_identity(lua_State *L, int base);
rvg::xform rvg_lua_xform_rotation(lua_State *L, int base);
rvg::xform rvg_lua_xform_scaling(lua_State *L, int base);
rvg::xform rvg_lua_xform_translation(lua_State *L, int base);
rvg::xform rvg_lua_xform_linearity(lua_State *L, int base);
rvg::xform rvg_lua_xform_affinity(lua_State *L, int base);
rvg::xform rvg_lua_xform_projectivity(lua_State *L, int base);
rvg::xform rvg_lua_xform_windowviewport(lua_State *L, int base);

#endif

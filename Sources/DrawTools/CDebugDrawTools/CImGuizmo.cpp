//
//  CImGuizmo.cpp
//  CGRAGame
//
//  Created by Thomas Roughton on 18/05/17.
//  Copyright © 2017 Team Llama. All rights reserved.
//

#include <stdio.h>
#include "CImGuizmo.h"
#include "ImGuizmo.h"

// call inside your own window and before Manipulate() in order to draw gizmo to that window.
CIMGUI_API void ImGuizmo_SetDrawList() {
    ImGuizmo::SetDrawlist();
}

// call BeginFrame right after ImGui_XXXX_NewFrame();
CIMGUI_API void ImGuizmo_BeginFrame() {
    ImGuizmo::BeginFrame();
}

// return true if mouse cursor is over any gizmo control (axis, plan or screen component)
CIMGUI_API bool ImGuizmo_IsOver() {
    return ImGuizmo::IsOver();
}

// return true if mouse IsOver or if the gizmo is in moving state
CIMGUI_API bool ImGuizmo_IsUsing() {
    return ImGuizmo::IsUsing();
}

// enable/disable the gizmo. Stay in the state until next call to Enable.
// gizmo is rendered with gray half transparent color when disabled
CIMGUI_API void ImGuizmo_Enable(bool enable) {
    ImGuizmo::Enable(enable);
}

// enable/disable the gizmo. Stay in the state until next call to Enable.
// gizmo is rendered with gray half transparent color when disabled
CIMGUI_API void ImGuizmo_SetOrthographic(bool isOrthographic) {
    ImGuizmo::SetOrthographic(isOrthographic);
}

// helper functions for manualy editing translation/rotation/scale with an input float
// translation, rotation and scale float points to 3 floats each
// Angles are in degrees (more suitable for human editing)
// example:
// float matrixTranslation[3], matrixRotation[3], matrixScale[3];
// ImGuizmo::DecomposeMatrixToComponents(gizmoMatrix.m16, matrixTranslation, matrixRotation, matrixScale);
// ImGui::InputFloat3("Tr", matrixTranslation, 3);
// ImGui::InputFloat3("Rt", matrixRotation, 3);
// ImGui::InputFloat3("Sc", matrixScale, 3);
// ImGuizmo::RecomposeMatrixFromComponents(matrixTranslation, matrixRotation, matrixScale, gizmoMatrix.m16);
//
// These functions have some numerical stability issues for now. Use with caution.
CIMGUI_API void ImGuizmo_DecomposeMatrixToComponents(const float *matrix, float *translation, float *rotation, float *scale) {
    ImGuizmo::DecomposeMatrixToComponents(matrix, translation, rotation, scale);
}
CIMGUI_API void ImGuizmo_RecomposeMatrixFromComponents(const float *translation, const float *rotation, const float *scale, float *matrix) {
    ImGuizmo::RecomposeMatrixFromComponents(translation, rotation, scale, matrix);
}

CIMGUI_API void ImGuizmo_SetRect(float x, float y, float width, float height) {
    ImGuizmo::SetRect(x, y, width, height);
}

// Render a cube with face color corresponding to face normal. Usefull for debug/tests
CIMGUI_API void ImGuizmo_DrawCube(const float *view, const float *projection, const float *matrix) {
    ImGuizmo::DrawCube(view, projection, matrix);
}

// Render a cube with face color corresponding to face normal. Usefull for debug/tests
CIMGUI_API void ImGuizmo_DrawGrid(const float *view, const float *projection, const float *matrix, const float gridSize) {
    ImGuizmo::DrawCube(view, projection, matrix);
}

CIMGUI_API void ImGuizmo_Manipulate(const float *view, const float *projection, ImGuizmoOperation operation, ImGuizmoMode mode, float *matrix, float *deltaMatrix, float *snap, float *localBounds, float *boundsSnap) {
    ImGuizmo::Manipulate(view, projection, static_cast<ImGuizmo::OPERATION>(operation), static_cast<ImGuizmo::MODE>(mode), matrix, deltaMatrix, snap, localBounds, boundsSnap);
}

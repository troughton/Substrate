//
//  CImGuizmo.h
//  CGRAGame
//
//  Created by Thomas Roughton on 18/05/17.
//  Copyright © 2017 Team Llama. All rights reserved.
//

#ifndef CImGuizmo_h
#define CImGuizmo_h

#include "cimgui.h"

CIMGUI_API void ImGuizmo_SetDrawList();

// call BeginFrame right after ImGui_XXXX_NewFrame();
CIMGUI_API void ImGuizmo_BeginFrame();

// return true if mouse cursor is over any gizmo control (axis, plan or screen component)
CIMGUI_API bool ImGuizmo_IsOver();

// return true if mouse IsOver or if the gizmo is in moving state
CIMGUI_API bool ImGuizmo_IsUsing();

// enable/disable the gizmo. Stay in the state until next call to Enable.
// gizmo is rendered with gray half transparent color when disabled
CIMGUI_API void ImGuizmo_Enable(bool enable);

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
CIMGUI_API void ImGuizmo_DecomposeMatrixToComponents(const float *matrix, float *translation, float *rotation, float *scale);
CIMGUI_API void ImGuizmo_RecomposeMatrixFromComponents(const float *translation, const float *rotation, const float *scale, float *matrix);

CIMGUI_API void ImGuizmo_SetRect(float x, float y, float width, float height);

CIMGUI_API void ImGuizmo_SetOrthographic(bool isOrthographic);

// Render a cube with face color corresponding to face normal. Usefull for debug/tests
CIMGUI_API void ImGuizmo_DrawCube(const float *view, const float *projection, const float *matrix);

CIMGUI_API void ImGuizmo_DrawGrid(const float *view, const float *projection, const float *matrix, const float gridSize);

// call it when you want a gizmo
// Needs view and projection matrices.
// matrix parameter is the source matrix (where will be gizmo be drawn) and might be transformed by the function. Return deltaMatrix is optional
// translation is applied in world space
typedef enum ImGuizmoOperation {
    ImGuizmoOperationTranslate,
    ImGuizmoOperationRotate,
    ImGuizmoOperationScale
} ImGuizmoOperation;

typedef enum ImGuizmoMode
{
    ImGuizmoModeLocal,
    ImGuizmoModeWorld
} ImGuizmoMode;

CIMGUI_API void ImGuizmo_Manipulate(const float *view, const float *projection, ImGuizmoOperation operation, ImGuizmoMode mode, float *matrix, float *deltaMatrix, float *snap, float *localBounds, float *boundsSnap);

#endif /* CImGuizmo_h */

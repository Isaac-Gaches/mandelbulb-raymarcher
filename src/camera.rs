
use std::f32::consts::PI;

use winit::event::{
    ElementState,
    MouseButton,
    MouseScrollDelta,
    WindowEvent,
};

pub struct Camera {
    pub pos: [f32; 3],
    pub target: [f32; 3],
    pub res: [f32; 2],

    yaw: f32,
    pitch: f32,
    distance: f32,

    orbit_sensitivity: f32,
    zoom_speed: f32,

    mouse_pressed: bool,
    last_mouse: Option<(f64, f64)>,
}

impl Camera {
    pub fn new() -> Self {
        Self {
            // Camera starts 4 units away from the origin.
            pos: [4.0, 0.0, 0.0],
            target: [0.0, 0.0, 0.0],
            res: [1.0, 1.0],

            // Starting rotation.
            yaw: 0.0,
            pitch: 0.0,

            // Orbit distance.
            distance: 4.0,

            // Mouse controls.
            orbit_sensitivity: 0.005,
            zoom_speed: 0.5,

            mouse_pressed: false,
            last_mouse: None,
        }
    }

    pub fn resize(&mut self, width: f32, height: f32) {
        self.res = [
            width.max(1.0),
            height.max(1.0),
        ];
    }

    pub fn input(&mut self, event: &WindowEvent) -> bool {
        match event {
            WindowEvent::MouseInput {
                state,
                button: MouseButton::Left,
                ..
            } => {
                self.mouse_pressed =
                    *state == ElementState::Pressed;

                if self.mouse_pressed {
                    // Start a fresh drag.
                    self.last_mouse = None;
                } else {
                    // Stop tracking the mouse.
                    self.last_mouse = None;
                }

                true
            }

            WindowEvent::CursorMoved { position, .. } => {
                if self.mouse_pressed {
                    if let Some((last_x, last_y)) = self.last_mouse {
                        let dx =
                            position.x - last_x;

                        let dy =
                            position.y - last_y;

                        // Horizontal mouse movement rotates
                        // around the target.
                        self.yaw -=
                            dx as f32 *
                                self.orbit_sensitivity;

                        // Vertical mouse movement rotates
                        // up/down.
                        self.pitch -=
                            dy as f32 *
                                self.orbit_sensitivity;

                        // Don't allow the camera to flip
                        // completely upside down.
                        self.pitch =
                            self.pitch.clamp(
                                -PI * 0.49,
                                PI * 0.49,
                            );
                    }

                    self.last_mouse =
                        Some((position.x, position.y));
                }

                true
            }

            WindowEvent::MouseWheel { delta, .. } => {
                let scroll = match delta {
                    MouseScrollDelta::LineDelta(_, y) => {
                        *y
                    }

                    MouseScrollDelta::PixelDelta(pos) => {
                        pos.y as f32 * 0.01
                    }
                };

                self.distance -=
                    scroll * self.zoom_speed;

                self.distance =
                    self.distance.clamp(
                        0.5,
                        20.0,
                    );

                true
            }

            _ => false,
        }
    }

    pub fn update(&mut self, _dt: f32) {
        let cos_pitch =
            self.pitch.cos();

        let sin_pitch =
            self.pitch.sin();

        let cos_yaw =
            self.yaw.cos();

        let sin_yaw =
            self.yaw.sin();

        // Direction from the target to the camera.
        let direction = [
            cos_pitch * cos_yaw,
            sin_pitch,
            cos_pitch * sin_yaw,
        ];

        // Orbit around the target.
        self.pos = [
            self.target[0]
                + direction[0] * self.distance,

            self.target[1]
                + direction[1] * self.distance,

            self.target[2]
                + direction[2] * self.distance,
        ];
    }
}



struct VertexInput {
    @location(0) quad_position: vec3<f32>,
};

struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
};

struct Uniform {
    resolution_time_fov: vec4<f32>,
    camera_position: vec4<f32>,
    camera_target: vec4<f32>,
};

@group(0) @binding(0)
var<uniform> buffer: Uniform;


// ============================================================================
// COLOURS
// ============================================================================

const BASE_COLOR: vec3<f32> = vec3<f32>(
    0.0,
    0.0,
    0.0
);

const OCCLUSION_COLOR: vec3<f32> = vec3<f32>(
    0.4,
    0.0,
    0.9
);


// ============================================================================
// MANDELBULB
// ============================================================================

const POWER_MIN: f32 = 6.;
const POWER_MAX: f32 = 10.0;

// Time in seconds for a complete power cycle.
const POWER_CYCLE: f32 = 15.0;

const MANDELBULB_ITERATIONS: i32 = 20;
const MANDELBULB_ESCAPE_RADIUS: f32 = 1.5;


// ============================================================================
// RAY MARCHING
// ============================================================================

const EPSILON: f32 = 0.0002;
const MAX_DISTANCE: f32 = 10.0;
const MAX_STEPS: i32 = 160;


// ============================================================================
// AMBIENT OCCLUSION
//
// This follows the AO calculation from your reference shader.
//
// More ray-marching steps = darker/more occluded.
// ============================================================================

const AO_STEP_SCALE: f32 = 0.015;
const AO_POWER: f32 = 2.0;


// ============================================================================
// VERTEX SHADER
// ============================================================================

@vertex
fn vs_main(
    in: VertexInput
) -> VertexOutput {
    var out: VertexOutput;

    out.clip_position = vec4<f32>(
        in.quad_position,
        1.0
    );

    return out;
}


// ============================================================================
// ANIMATED MANDELBULB POWER
// ============================================================================

fn animated_power(
    time: f32
) -> f32 {
    let phase =
        (time / POWER_CYCLE) *
        2.0 *
        3.14159265359;

    // Smoothly oscillates between 0 and 1.
    let t =
        0.5 +
        0.5 * sin(phase);

    return mix(
        POWER_MIN,
        POWER_MAX,
        t
    );
}


// ============================================================================
// MANDELBULB DISTANCE ESTIMATOR
// ============================================================================

fn mandelbulb_sdf(
    pos: vec3<f32>,
    time: f32
) -> f32 {
    let power =
        animated_power(time);

    var z = pos;

    var dr: f32 = 1.0;
    var r: f32 = 0.0;

    for (
        var i: i32 = 0;
        i < MANDELBULB_ITERATIONS;
        i++
    ) {
        r = length(z);

        if (
            r > MANDELBULB_ESCAPE_RADIUS
        ) {
            break;
        }

        // --------------------------------------------------------------------
        // Convert to polar coordinates.
        // --------------------------------------------------------------------

        let theta =
            acos(
                clamp(
                    z.z / max(r, 0.000001),
                    -1.0,
                    1.0
                )
            );

        let phi =
            atan2(
                z.y,
                z.x
            );

        // --------------------------------------------------------------------
        // Derivative estimate.
        // --------------------------------------------------------------------

        dr =
            pow(
                r,
                power - 1.0
            )
            * power
            * dr
            + 1.0;

        // --------------------------------------------------------------------
        // Scale and rotate.
        // --------------------------------------------------------------------

        let zr =
            pow(
                r,
                power
            );

        let new_theta =
            theta * power;

        let new_phi =
            phi * power;

        // --------------------------------------------------------------------
        // Convert back to Cartesian coordinates.
        // --------------------------------------------------------------------

        z =
            pos +
            zr *
            vec3<f32>(
                sin(new_theta) * cos(new_phi),
                sin(new_theta) * sin(new_phi),
                cos(new_theta)
            );
    }

    return
        0.5 *
        log(r) *
        r /
        dr;
}


// ============================================================================
// SCENE SDF
// ============================================================================

fn scene_sdf(
    position: vec3<f32>,
    time: f32
) -> f32 {
    return mandelbulb_sdf(
        position,
        time
    );
}


// ============================================================================
// RAY MARCHING
//
// depth:
//     Total distance travelled by the ray.
//
// steps:
//     Number of SDF evaluations.
//
// The step count is later used as the AO value.
// ============================================================================

fn ray_marching(
    eye: vec3<f32>,
    ray: vec3<f32>,
    time: f32,
    depth: ptr<function, f32>,
    steps: ptr<function, f32>
) -> vec3<f32> {

    *depth = 0.0;
    *steps = 0.0;

    var distance: f32 = 0.0;

    var intersection_point =
        eye;

    for (
        var i: i32 = 0;
        i < MAX_STEPS;
        i++
    ) {
        distance =
            scene_sdf(
                intersection_point,
                time
            );

        intersection_point +=
            distance * ray;

        *depth += distance;
        *steps += 1.0;

        if (
            *depth >= MAX_DISTANCE ||
            distance <= EPSILON
        ) {
            break;
        }
    }

    return intersection_point;
}


// ============================================================================
// AMBIENT OCCLUSION
//
// This is intentionally based on the reference shader:
//
//     float ao = steps * 0.015;
//     ao = 1. - ao / (ao + 1.0);
//     ao = pow(ao, 2.);
//
// It produces darker colour where the ray requires more SDF steps to reach
// the surface.
// ============================================================================

fn ambient_occlusion(
    steps: f32
) -> f32 {

    var ao =
        steps *
        AO_STEP_SCALE;

    // Reinhard remapping.
    ao =
        1.0 -
        ao / (ao + 1.0);

    // Increase contrast.
    ao =
        pow(
            ao,
            AO_POWER
        );

    return clamp(
        ao,
        0.0,
        1.0
    );
}


// ============================================================================
// FRAGMENT SHADER
// ============================================================================

@fragment
fn fs_main(
    in: VertexOutput
) -> @location(0) vec4<f32> {

    // ------------------------------------------------------------------------
    // Uniforms
    // ------------------------------------------------------------------------

    let resolution =
        buffer.resolution_time_fov.xy;

    let time =
        buffer.resolution_time_fov.z;

    let fov =
        buffer.resolution_time_fov.w;


    // ------------------------------------------------------------------------
    // Screen coordinates
    // ------------------------------------------------------------------------

    var coord =
        (in.clip_position.xy / resolution) *
        2.0 -
        1.0;

    // Match the coordinate transform from the reference shader.
    coord.y *=
        resolution.y /
        resolution.x;


    // ------------------------------------------------------------------------
    // Camera basis
    // ------------------------------------------------------------------------

    let camera_position =
        buffer.camera_position.xyz;

    let camera_target =
        buffer.camera_target.xyz;

    let forward =
        normalize(
            camera_target -
            camera_position
        );

    let world_up =
        vec3<f32>(
            0.0,
            1.0,
            0.0
        );

    let right =
        normalize(
            cross(
                forward,
                world_up
            )
        );

    let up =
        normalize(
            cross(
                right,
                forward
            )
        );


    // ------------------------------------------------------------------------
    // Ray direction
    // ------------------------------------------------------------------------

    let ray_direction =
        normalize(
            forward
            +
            right *
            coord.x *
            tan(fov * 0.5)
            +
            up *
            coord.y *
            tan(fov * 0.5)
        );


    // ------------------------------------------------------------------------
    // Ray march
    // ------------------------------------------------------------------------

    var depth: f32 = 0.0;
    var steps: f32 = 0.0;

    let intersection_point =
        ray_marching(
            camera_position +
                EPSILON * ray_direction,
            ray_direction,
            time,
            &depth,
            &steps
        );



    // ------------------------------------------------------------------------
    // Ambient occlusion
    // ------------------------------------------------------------------------

    let ao =
        ambient_occlusion(
            steps
        );


    // ------------------------------------------------------------------------
    // Colour
    //
    // AO = 0:
    //     OCCLUSION_COLOR
    //
    // AO = 1:
    //     BASE_COLOR
    // ------------------------------------------------------------------------

    let color =
        mix(
            OCCLUSION_COLOR,
            BASE_COLOR,
            ao
        );


    // ------------------------------------------------------------------------
    // Output
    // ------------------------------------------------------------------------

    return vec4<f32>(
        color,
        1.0
    );
}

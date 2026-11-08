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

const BASE_COLOR: vec3<f32> = vec3<f32>(
    0.0,
    0.0,
    0.0
);

const OCCLUSION_COLOR: vec3<f32> = vec3<f32>(
    1.,
    1.,
    1.
);


const POWER_MIN: f32 = 6.;
const POWER_MAX: f32 = 10.0;

const POWER_CYCLE: f32 = 15.0;

const MANDELBULB_ITERATIONS: i32 = 20;
const MANDELBULB_ESCAPE_RADIUS: f32 = 1.5;

const EPSILON: f32 = 0.0002;
const MAX_DISTANCE: f32 = 10.0;
const MAX_STEPS: i32 = 160;

const AO_STEP_SCALE: f32 = 0.015;
const AO_POWER: f32 = 2.0;

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

fn animated_power(
    time: f32
) -> f32 {
    let phase =
        (time / POWER_CYCLE) *
        2.0 *
        3.14159265359;

    let t =
        0.5 +
        0.5 * sin(phase);

    return mix(
        POWER_MIN,
        POWER_MAX,
        t
    );
}

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

        dr =
            pow(
                r,
                power - 1.0
            )
            * power
            * dr
            + 1.0;

        let zr =
            pow(
                r,
                power
            );

        let new_theta =
            theta * power;

        let new_phi =
            phi * power;

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

fn scene_sdf(
    position: vec3<f32>,
    time: f32
) -> f32 {
    return mandelbulb_sdf(
        position,
        time
    );
}

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

fn ambient_occlusion(
    steps: f32
) -> f32 {

    var ao =
        steps *
        AO_STEP_SCALE;

    ao =
        1.0 -
        ao / (ao + 1.0);

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

@fragment
fn fs_main(
    in: VertexOutput
) -> @location(0) vec4<f32> {
    let resolution =
        buffer.resolution_time_fov.xy;

    let time =
        buffer.resolution_time_fov.z;

    let fov =
        buffer.resolution_time_fov.w;

    var coord =
        (in.clip_position.xy / resolution) *
        2.0 -
        1.0;

    coord.y *=
        resolution.y /
        resolution.x;

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

    let ao =
        ambient_occlusion(
            steps
        );

    let color =
        mix(
            OCCLUSION_COLOR,
            BASE_COLOR,
            ao
        );

    return vec4<f32>(
        color,
        1.0
    );
}

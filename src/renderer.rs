use std::sync::Arc;
use winit::event::WindowEvent;
use winit::window::Window;
use easy_gpu::assets::*;
use easy_gpu::assets_manager::*;
use easy_gpu::wgpu::{TextureFormat, VertexFormat};
use easy_gpu::Renderer;
use winit::dpi::PhysicalSize;
use crate::camera::Camera;

#[repr(C)]
#[derive(Debug, Copy, Clone, bytemuck::Pod, bytemuck::Zeroable)]
struct Vertex{
    position: [f32;2],
}
impl Vertex {
    pub fn new(position: [f32;2]) -> Self {
        Vertex{position}
    }
}
impl GpuVertex for Vertex {
    fn buffer_layout() -> BufferLayout {
        BufferLayout::new()
            .stride(size_of::<Self>() as u64)
            .attribute(0,0,VertexFormat::Float32x2)
    }
}

pub struct Render{
    egpu: Renderer,
    buffer: Handle<Buffer>,
    camera: Camera,
    material: Handle<Material>,
    mesh: Handle<Mesh>,
}

impl Render{
    pub fn new(window: Arc<Window>)->Self{
        let mut egpu = pollster::block_on(Renderer::new(window.clone()));

        let scale = 4.0;
        let vertices = [
            Vertex::new([-scale, -scale]),
            Vertex::new([scale, -scale]),
            Vertex::new([scale, scale]),
            Vertex::new([-scale, scale])
        ];
        let indices = [0, 1, 2, 0, 2, 3];
        let mesh = egpu.create_mesh(&vertices, &indices);

        let camera = Camera::new();

        let buffer = egpu.create_buffer(
            BufferUsages::UNIFORM | BufferUsages::COPY_DST,
            size_of::<Camera>() as u64
        );

        let shader = egpu.load_shader(include_str!("raymarcher.wgsl"));

        let pipeline = RenderPipelineBuilder::new(shader)
            .vertex_layout(Vertex::buffer_layout())
            .material_layout(&[render_uniform(0)])
            .depth_format(TextureFormat::Depth24Plus)
            .depth_writes_enabled(false)
            .additive_alpha_blending()
            .build(&mut egpu);

        let material = MaterialBuilder::new(pipeline)
            .buffer(0,buffer)
            .build(&mut egpu);

        Self{
            egpu,
            buffer,
            camera,
            material,
            mesh,
        }
    }

    pub fn update(&mut self, dt: f32, time: f32){
        self.camera.update(dt);

        self.egpu.write_buffer(
            self.buffer,
            Uniform{
                resolution_time_fov: [self.camera.res[0],self.camera.res[1],time,1.0],
                camera_pos: [self.camera.pos[0],self.camera.pos[1],-self.camera.pos[2],0.],
                target: [self.camera.target[0],self.camera.target[1],self.camera.target[2],0.],
            }
        );
    }

    pub fn render(&mut self){
        let frame = self.egpu.begin_frame();

        frame.draw(
            self.material,
            self.mesh,
        );

        self.egpu.render();
    }

    pub fn resize(&mut self, size: PhysicalSize<u32>){
        self.egpu.resize_surface(size);
        self.camera.resize(size.width as f32, size.height as f32);
    }

    pub fn handle_input(&mut self, event: &WindowEvent){
        self.camera.input(event);
    }
}

#[repr(C)]
#[derive(Debug, Copy, Clone, bytemuck::Pod, bytemuck::Zeroable)]
pub struct Uniform{
    resolution_time_fov: [f32;4],
    camera_pos: [f32;4],
    target: [f32;4],
}
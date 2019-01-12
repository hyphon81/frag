import
  math

import
  bgfxdotnim as bgfx

import
  ../../logger,
  ../../math/fpu_math as fpumath,
  ../../modules/graphics,
  ../types,
  texture,
  texture_atlas,
  texture_region,
  ../../util,
  vertex
  
when defined(windows):
  import
    dx/fs_default_dx9,
    dx/vs_default_dx9,
    dx/fs_default_dx11,
    dx/vs_default_dx11

else:
  import
    gl/fs_default,
    gl/vs_default


type
  SpriteBatch* = ref object
    vertices: seq[PosUVColorVertex]
    maxSprites: int
    lastTexture: Texture
    drawing: bool
    programHandle: bgfx_program_handle_t
    ibh: bgfx_index_buffer_handle_t
    vDecl: ptr bgfx_vertex_decl_t
    texHandle: bgfx_uniform_handle_t
    view: uint8
    blendSrcFunc*, blendDstFunc*: BlendFunc
    blendingEnabled*: bool
    projectionMatrix*: fpumath.Mat4

proc setProjectionMatrix*(batch: SpriteBatch, projectionMatrix: fpumath.Mat4) =
  discard
  batch.projectionMatrix = projectionMatrix
  bgfx_set_view_transform(batch.view, nil, addr batch.projectionMatrix[0])

proc flush(spriteBatch: SpriteBatch) =
  if spriteBatch.lastTexture.isNil:
    return

  let spriteCount = spriteBatch.vertices.len / 4

  var vb : bgfx_transient_vertex_buffer_t
  bgfx_alloc_transient_vertex_buffer(addr vb, uint32 spriteBatch.vertices.len, spriteBatch.vDecl);
  copyMem(vb.data, addr spriteBatch.vertices[0], sizeof(PosUVColorVertex) * spriteBatch.vertices.len)

  bgfx_set_texture(0, spriteBatch.texHandle, spriteBatch.lastTexture.handle, high(uint32))
  bgfx_set_transient_vertex_buffer(0, addr vb, 0u32, uint32 spriteBatch.vertices.len)
  bgfx_set_index_buffer(spriteBatch.ibh, 0, uint32 spriteCount * 6)

  var mtx: fpumath.Mat4
  mtxIdentity(mtx)

  discard bgfx_set_transform(addr mtx[0], 1)

  if spriteBatch.blendingEnabled:
    bgfx_set_state(0'u64 or BGFX_STATE_WRITE_RGB or BGFX_STATE_BLEND_FUNC(BGFX_STATE_BLEND_SRC_ALPHA
      , BGFX_STATE_BLEND_INV_SRC_ALPHA), 0)
  else:
    bgfx_set_state(BGFX_STATE_DEFAULT, 0)

  bgfx_submit(spriteBatch.view, spriteBatch.programHandle, 0, false)

  spriteBatch.vertices.setLen(0)

proc switchTexture(spriteBatch: SpriteBatch, texture: Texture) =
  flush(spriteBatch)
  spriteBatch.lastTexture = texture

proc drawRegion*(spriteBatch: SpriteBatch, textureRegion: TextureRegion, x, y: float32, color: uint32 = 0xffffffff'u32) =
  if not spriteBatch.drawing:
    logError "Spritebatch not in drawing mode. Call begin before calling draw."
    return

  let texture = textureRegion.texture

  if texture != spriteBatch.lastTexture:
    switchTexture(spriteBatch, texture)

  spriteBatch.vertices.add([
    PosUVColorVertex(x: x, y: y, z: 0.0'f32, u:textureRegion.u, v:textureRegion.v, abgr: color ),
    PosUVColorVertex(x: x + float textureRegion.regionWidth, y: y, z: 0.0'f32, u:textureRegion.u2, v:textureRegion.v, abgr: color ),
    PosUVColorVertex(x: x + float textureRegion.regionWidth, y: y + float textureRegion.regionHeight, z: 0.0'f32, u:textureRegion.u2, v:textureRegion.v2, abgr: color ),
    PosUVColorVertex(x: x, y: y + float textureRegion.regionHeight, z: 0.0'f32, u:textureRegion.u, v:textureRegion.v2, abgr: color ),
  ])

proc draw*(spriteBatch: SpriteBatch, texture: Texture, vertices: openArray[PosUVColorVertex]) =
  if not spriteBatch.drawing:
    logError "Spritebatch not in drawing mode. Call begin before calling draw."
    return

  if texture != spriteBatch.lastTexture:
    switchTexture(spriteBatch, texture)

  spriteBatch.vertices.add(vertices)

proc draw*(spriteBatch: SpriteBatch, texture: Texture, x, y, width, height: float32, tiled: bool = false, color: uint32 = 0xffffffff'u32, scale: Vec3 = [1.0'f32, 1.0'f32, 1.0'f32], rotation: float = 0) =
  if not spriteBatch.drawing:
    logError "Spritebatch not in drawing mode. Call begin before calling draw."
    return

  if texture != spriteBatch.lastTexture:
    switchTexture(spriteBatch, texture)

  var originX, originY = 0.0
  let worldOriginX = x + originX
  let worldOriginY = y + originY
  var fx = -originX
  var fx2 = width - originX
  var fy = -originY
  var fy2 = height - originY

  if scale[0] != 1.0'f32 or scale[1] != 1.0'f32:
    fx *= scale[0]
    fx2 *= scale[0]
    fy *= scale[1]
    fy2 *= scale[1]

  let p1x = fx
  let p1y = fy
  let p2x = fx
  let p2y = fy2
  let p3x = fx2
  let p3y = fy2
  let p4x = fx2
  let p4y = fy

  var x1, y1, x2, y2, x3, y3, x4, y4: float

  if rotation != 0:
    let cos = cos(degToRad(rotation))
    let sin = sin(degToRad(rotation))

    x1 = cos * p1x - sin * p1y
    y1 = sin * p1x + cos * p1y

    x2 = cos * p2x - sin * p2y
    y2 = sin * p2x + cos * p2y

    x3 = cos * p3x - sin * p3y
    y3 = sin * p3x + cos * p3y

    x4 = x1 + (x3 - x2)
    y4 = y3 - (y2 - y1)
  
  else:
    x1 = p1x
    y1 = p1y

    x2 = p2x
    y2 = p2y

    x3 = p3x
    y3 = p3y

    x4 = p4x
    y4 = p4y

  
  x1 += worldOriginX;
  y1 += worldOriginY;
  x2 += worldOriginX;
  y2 += worldOriginY;
  x3 += worldOriginX;
  y3 += worldOriginY;
  x4 += worldOriginX;
  y4 += worldOriginY;


  var maxUV = 1.0
  if tiled: maxUV = 8.0
  spriteBatch.vertices.add([
    PosUVColorVertex(x: x1, y: y1, u:0.0, v:maxUV, z: 0.0'f32, abgr: color ),
    PosUVColorVertex(x: x2, y: y2, u:0.0, v:0.0, z: 0.0'f32, abgr: color ),
    PosUVColorVertex(x: x3, y: y3, u:maxUV, v:0.0, z: 0.0'f32, abgr: color ),
    PosUVColorVertex(x: x4, y: y4, u:maxUV, v:maxUV, z: 0.0'f32, abgr: color )
  ])

proc init*(spriteBatch: SpriteBatch, maxSprites: int, view: uint8) =
  spriteBatch.drawing = false
  spriteBatch.maxSprites = maxSprites
  spriteBatch.vertices = @[]
  
  spriteBatch.view = view
   
  mtxIdentity(spriteBatch.projectionMatrix)

  spriteBatch.vDecl = workaround_createShared[bgfx_vertex_decl_t]()

  let indicesCount = maxSprites * 6

  var indexdata = newSeq[uint16](indicesCount)
  var i = 0
  var j = 0u16
  while i < indicesCount:
    indexdata[i] = j
    indexdata[i + 1] = j + 1
    indexdata[i + 2] = j + 2
    indexdata[i + 3] = j + 2
    indexdata[i + 4] = j + 3
    indexdata[i + 5] = j
    inc(j, 4)
    inc(i, 6)

  spriteBatch.ibh = bgfx_create_index_buffer(bgfx_copy(addr indexdata[0], uint32 indexdata.len * sizeof(uint16)), BGFX_BUFFER_NONE)

  bgfx_vertex_decl_begin(spriteBatch.vDecl, BGFX_RENDERER_TYPE_NOOP)
  bgfx_vertex_decl_add(spriteBatch.vDecl, BGFX_ATTRIB_POSITION, 3, BGFX_ATTRIB_TYPE_FLOAT, false, false)
  bgfx_vertex_decl_add(spriteBatch.vDecl, BGFX_ATTRIB_TEXCOORD0, 2, BGFX_ATTRIB_TYPE_FLOAT, false, false)
  bgfx_vertex_decl_add(spriteBatch.vDecl, BGFX_ATTRIB_COLOR0, 4, BGFX_ATTRIB_TYPE_UINT8, true, false)
  bgfx_vertex_decl_end(spriteBatch.vDecl)

  spriteBatch.texHandle = bgfx_create_uniform("s_texColor", BGFX_UNIFORM_TYPE_INT1, 1)

  var vsh, fsh : bgfx_shader_handle_t
  when defined(windows):
    case bgfx_get_renderer_type()
    of BGFX_RENDERER_TYPE_DIRECT3D9:
      vsh = bgfx_create_shader(bgfx_make_ref(addr vs_default_dx9.vs[0], uint32 sizeof(vs_default_dx9.vs)))
      fsh = bgfx_create_shader(bgfx_make_ref(addr fs_default_dx9.fs[0], uint32 sizeof(fs_default_dx9.fs)))
    of BGFX_RENDERER_TYPE_DIRECT3D11:
      vsh = bgfx_create_shader(bgfx_make_ref(addr vs_default_dx11.vs[0], uint32 sizeof(vs_default_dx11.vs)))
      fsh = bgfx_create_shader(bgfx_make_ref(addr fs_default_dx11.fs[0], uint32 sizeof(fs_default_dx11.fs)))
    else:
      discard
  else:
    vsh = bgfx_create_shader(bgfx_make_ref(addr vs_default.vs[0], uint32 sizeof(vs_default.vs)))
    fsh = bgfx_create_shader(bgfx_make_ref(addr fs_default.fs[0], uint32 sizeof(fs_default.fs)))
  spriteBatch.programHandle = bgfx_create_program(vsh, fsh, true)

proc begin*(spriteBatch: SpriteBatch) =
  if spriteBatch.drawing:
    logError "Spritebatch is already in drawing mode. Call end before calling begin."
    return

  spriteBatch.drawing = true

proc `end`*(spriteBatch: SpriteBatch) =
  if not spriteBatch.drawing:
    logError "Spritebatch is not currently in drawing mode. Call begin before calling end."
    return

  if spriteBatch.vertices.len > 0:
    flush(spriteBatch)

  spriteBatch.lastTexture = nil
  spriteBatch.drawing = false

proc dispose*(spriteBatch: SpriteBatch) =
  bgfx_destroy_uniform(spriteBatch.texHandle)
  bgfx_destroy_index_buffer(spriteBatch.ibh)
  let rendererType = bgfx_get_renderer_type()
  if rendererType in [BGFX_RENDERER_TYPE_OPENGL, BGFX_RENDERER_TYPE_OPENGLES]:
    if spriteBatch.programHandle.idx != 65535'u16:
      bgfx_destroy_program(spriteBatch.programHandle)

  freeShared(spriteBatch.vDecl)

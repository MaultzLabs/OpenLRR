// DirectDraw.cpp : 
//

#include "../../platform/windows.h"
#include "../../platform/ddraw.h"
#include "../../platform/d3drm.h"

#include "../core/Errors.h"
#include "../core/Files.h"
#include "../core/Memory.h"
#include "../util/Dxbug.h"
#include "../Graphics.h"
#include "../Main.h"
#include "../util/MenuPerf.h"
#include "Bmp.h"
#include "Draw.h"

#include "DirectDraw.h"


/**********************************************************************************
 ******** Constants
 **********************************************************************************/

#pragma region Constants

#pragma endregion

/**********************************************************************************
 ******** Globals
 **********************************************************************************/

#pragma region Globals

// <LegoRR.exe @0076bc80>
Gods98::DirectDraw_Globs & Gods98::directDrawGlobs = *(Gods98::DirectDraw_Globs*)0x0076bc80;

/// CUSTOM:
static uint32 _directDrawBitDepth = 0;

#pragma endregion

/**********************************************************************************
 ******** Functions
 **********************************************************************************/

#pragma region Functions

// <LegoRR.exe @00406500>
IDirectDraw4* __cdecl Gods98::noinline(DirectDraw)(void)
{
	log_firstcall();

	return DirectDraw();
}

// <LegoRR.exe @00406510>
IDirectDrawSurface4* __cdecl Gods98::noinline(DirectDraw_bSurf)(void)
{
	log_firstcall();

	return DirectDraw_bSurf();
}

/*
// <unused>
__inline IDirectDrawSurface4* __cdecl Gods98::DirectDraw_fSurf()
{
	return directDrawGlobs.fSurf;
}

// <unused>
__inline bool32 __cdecl Gods98::DirectDraw_FullScreen()
{
	return directDrawGlobs.fullScreen;
}
*/


//__inline bool32 __cdecl DirectDraw_SetupFullScreen(lpDirectDraw_Driver driver, lpDirectDraw_Device device, lpDirectDraw_Mode mode)	{ return DirectDraw_Setup(true, driver, device, mode, 0, 0, 320, 200); }
//__inline bool32 __cdecl DirectDraw_SetupWindowed(lpDirectDraw_Device device, ULONG xPos, ULONG yPos, ULONG width, ULONG height)		{ return DirectDraw_Setup(false, nullptr, device, nullptr, xPos, yPos, width, height); }


// <LegoRR.exe @0047c430>
void __cdecl Gods98::DirectDraw_Initialise(HWND hWnd)
{
	log_firstcall();

	directDrawGlobs.driverCount = 0;
	directDrawGlobs.driverList  = nullptr;
	directDrawGlobs.deviceCount = 0;
	directDrawGlobs.deviceList  = nullptr;
	directDrawGlobs.modeCount   = 0;
	directDrawGlobs.modeList    = nullptr;
	directDrawGlobs.hWnd = hWnd;

	directDrawGlobs.lpDirectDraw = nullptr;
	directDrawGlobs.fSurf = directDrawGlobs.bSurf = directDrawGlobs.zSurf = nullptr;

	/// FIX APPLY: lpFrontClipper was assigned twice, instead of assigning lpBackClipper
	directDrawGlobs.lpFrontClipper = directDrawGlobs.lpBackClipper = nullptr;
}

// <LegoRR.exe @0047c480>
bool32 __cdecl Gods98::DirectDraw_EnumDrivers(OUT Graphics_Driver* list, OUT uint32* count)
{
	log_firstcall();

	directDrawGlobs.driverList = list;
	// Enumerate each driver and record its GUID and description
	legacy::DirectDrawEnumerateA(DirectDraw_EnumDriverCallback, nullptr);

	*count = directDrawGlobs.driverCount;
	return true;
}

// <LegoRR.exe @0047c4b0>
BOOL __stdcall Gods98::DirectDraw_EnumDriverCallback(GUID* lpGUID, char* lpDriverDescription, char* lpDriverName, void* lpContext)
{
	directDrawGlobs.driverList[directDrawGlobs.driverCount].flags = Graphics_DriverFlags::GRAPHICS_DRIVER_FLAG_VALID;

	// Record the GUID
	if (lpGUID != nullptr) directDrawGlobs.driverList[directDrawGlobs.driverCount].guid = *lpGUID;
	else directDrawGlobs.driverList[directDrawGlobs.driverCount].flags |= Graphics_DriverFlags::GRAPHICS_DRIVER_FLAG_PRIMARY;

#pragma message ( "TODO: Find out if driver can work in a window" )
	if (lpGUID == nullptr) directDrawGlobs.driverList[directDrawGlobs.driverCount].flags |= Graphics_DriverFlags::GRAPHICS_DRIVER_FLAG_WINDOWOK;

	std::sprintf(directDrawGlobs.driverList[directDrawGlobs.driverCount].desc, "%s (%s)", lpDriverDescription, lpDriverName);

	directDrawGlobs.driverCount++;

	return true;
}

// <LegoRR.exe @0047c5a0>
bool32 __cdecl Gods98::DirectDraw_EnumDevices(const Graphics_Driver* driver, OUT Graphics_Device* list, OUT uint32* count)
{
	log_firstcall();

	bool32 res = false;

	directDrawGlobs.deviceCount = 0;

	/// FIXME: Passing const_cast<GUID*>(&driver->guid) instead of assigned guid local variable
	GUID* guid = nullptr;
	if (driver->flags & Graphics_DriverFlags::GRAPHICS_DRIVER_FLAG_PRIMARY) guid = nullptr;
	else guid = const_cast<GUID*>(&driver->guid);

	IDirectDraw* lpDD1;
	if (legacy::DirectDrawCreate(const_cast<GUID*>(&driver->guid), &lpDD1, nullptr) == DD_OK) {
		IDirectDraw4* lpDD = nullptr; // dummy init
		if (lpDD1->QueryInterface(IID_IDirectDraw4, (void**)&lpDD) == DD_OK) {

			IDirect3D3* lpD3D = nullptr; // dummy init
			if (lpDD->QueryInterface(IID_IDirect3D3, (void**)&lpD3D) == DD_OK) {

				directDrawGlobs.deviceList = list;
				lpD3D->EnumDevices(DirectDraw_EnumDeviceCallback, nullptr);
				res = true;

				lpD3D->Release();
			} else Error_Warn(true, "Unable to obtain Direct3D3");
			lpDD->Release();
		} else Error_Warn(true, "Unable to obtain DirectDraw4");
		lpDD1->Release();
	} else Error_Warn(true, "Unable to create DirectDraw");

	*count = directDrawGlobs.deviceCount;

	return res;
}

// <LegoRR.exe @0047c640>
HRESULT __stdcall Gods98::DirectDraw_EnumDeviceCallback(GUID* lpGuid, char* lpDeviceDescription,
														char* lpDeviceName, D3DDEVICEDESC* lpHWDesc,
														D3DDEVICEDESC* lpHELDesc, void* lpContext)
{
	Graphics_Device* dev = &directDrawGlobs.deviceList[directDrawGlobs.deviceCount];
	D3DDEVICEDESC* desc;

	dev->flags = Graphics_DeviceFlags::GRAPHICS_DEVICE_FLAG_VALID;
	if (lpHWDesc->dcmColorModel != 0){
		dev->flags |= Graphics_DeviceFlags::GRAPHICS_DEVICE_FLAG_HARDWARE;
		desc = lpHWDesc;
	} else desc = lpHELDesc;

	if (desc->dwFlags & D3DDD_COLORMODEL) if (desc->dcmColorModel == D3DCOLOR_RGB) dev->flags |= Graphics_DeviceFlags::GRAPHICS_DEVICE_FLAG_COLOUR;
	if (desc->dwFlags & D3DDD_DEVICERENDERBITDEPTH){
		if (desc->dwDeviceRenderBitDepth & DDBD_8) dev->flags |= Graphics_DeviceFlags::GRAPHICS_DEVICE_FLAG_DEPTH8;
		if (desc->dwDeviceRenderBitDepth & DDBD_16) dev->flags |= Graphics_DeviceFlags::GRAPHICS_DEVICE_FLAG_DEPTH16;
		if (desc->dwDeviceRenderBitDepth & DDBD_24) dev->flags |= Graphics_DeviceFlags::GRAPHICS_DEVICE_FLAG_DEPTH24;
		if (desc->dwDeviceRenderBitDepth & DDBD_32) dev->flags |= Graphics_DeviceFlags::GRAPHICS_DEVICE_FLAG_DEPTH32;
	}

	if (desc->dwFlags & D3DDD_DEVCAPS){
		if (desc->dwDevCaps & D3DDEVCAPS_TEXTUREVIDEOMEMORY) dev->flags |= Graphics_DeviceFlags::GRAPHICS_DEVICE_FLAG_VIDEOTEXTURE;
		else if (desc->dwDevCaps & D3DDEVCAPS_TEXTURESYSTEMMEMORY) dev->flags |= Graphics_DeviceFlags::GRAPHICS_DEVICE_FLAG_SYSTEMTEXTURE;
	}

	dev->guid = *lpGuid;
	std::sprintf(dev->desc, "%s (%s)", lpDeviceName, lpDeviceDescription);

	directDrawGlobs.deviceCount++;

	return D3DENUMRET_OK;
}

// <LegoRR.exe @0047c770>
bool32 __cdecl Gods98::DirectDraw_EnumModes(const Graphics_Driver* driver, bool32 fullScreen, OUT Graphics_Mode* list, OUT uint32* count)
{
	log_firstcall();

	bool32 res = false;

	directDrawGlobs.modeCount = 0;

	if (driver) {
		if (driver->flags & Graphics_DriverFlags::GRAPHICS_DRIVER_FLAG_VALID) {

			GUID* guid = nullptr;
			if (!(driver->flags & Graphics_DriverFlags::GRAPHICS_DRIVER_FLAG_PRIMARY))
				guid = const_cast<GUID*>(&driver->guid);

			IDirectDraw* lpDD1;
			if (legacy::DirectDrawCreate(guid, &lpDD1, nullptr) == DD_OK) {
				IDirectDraw4* lpDD = nullptr; // dummy init
				if (lpDD1->QueryInterface(IID_IDirectDraw4, (void**)&lpDD) == DD_OK) {
					
					directDrawGlobs.modeList = list;
					lpDD->EnumDisplayModes(0, nullptr, &fullScreen, DirectDraw_EnumModeCallback);
					res = true;
					
					lpDD->Release();
				} else Error_Warn(true, "Unable to obtain DirectDraw2");
				lpDD1->Release();
			} else Error_Warn(true, "Unable to create DirectDraw");
		} else Error_Fatal(true, "Invalid driver passed to DirectDraw_EnumModes()");
	} else Error_Fatal(true, "NULL passed as driver to DirectDraw_EnumModes()");
			
	*count = directDrawGlobs.modeCount;
	return res;
}

// <LegoRR.exe @0047c810>
HRESULT __stdcall Gods98::DirectDraw_EnumModeCallback(DDSURFACEDESC2* lpDDSurfaceDesc, void* lpContext)
{
	Graphics_Mode* mode = &directDrawGlobs.modeList[directDrawGlobs.modeCount];
	bool32 fullScreen = *(bool32*)lpContext;

	mode->flags = Graphics_ModeFlags::GRAPHICS_MODE_FLAG_VALID;
	mode->width = lpDDSurfaceDesc->dwWidth;
	mode->height = lpDDSurfaceDesc->dwHeight;
	mode->bitDepth = lpDDSurfaceDesc->ddpfPixelFormat.dwRGBBitCount;

	/// CHANGE: Always show bit depth.
	std::sprintf(mode->desc, "%ix%i (%i bit)", lpDDSurfaceDesc->dwWidth, lpDDSurfaceDesc->dwHeight, lpDDSurfaceDesc->ddpfPixelFormat.dwRGBBitCount);

	/// TODO: What is this count check doing!??
	if (!fullScreen && directDrawGlobs.modeCount) {
		if (mode->bitDepth == Graphics_GetWindowsBitDepth()) directDrawGlobs.modeCount++;
		else mode->flags &= ~Graphics_ModeFlags::GRAPHICS_MODE_FLAG_VALID;
	} else directDrawGlobs.modeCount++;

	return D3DENUMRET_OK;
}

// <LegoRR.exe @0047c8d0>
bool32 __cdecl Gods98::DirectDraw_Setup(bool32 fullscreen, const Graphics_Driver* driver, const Graphics_Device* device,
										const Graphics_Mode* mode, uint32 xPos, uint32 yPos, uint32 width, uint32 height)
{
	log_firstcall();

	if (driver && !(driver->flags & Graphics_DriverFlags::GRAPHICS_DRIVER_FLAG_VALID)) driver = nullptr;
	if (device && !(device->flags & Graphics_DeviceFlags::GRAPHICS_DEVICE_FLAG_VALID)) device = nullptr;
	if (mode   && !(mode->flags   & Graphics_ModeFlags::GRAPHICS_MODE_FLAG_VALID))     mode   = nullptr;

	uint32 bpp = Graphics_GetWindowsBitDepth();
	if (mode) { // mode has priority over passed width/height values
		width  = mode->width;
		height = mode->height;
		bpp    = mode->bitDepth;
	}

	_directDrawBitDepth = bpp;
	directDrawGlobs.width = width;
	directDrawGlobs.height = height;
	directDrawGlobs.fullScreen = fullscreen;

	GUID* guid = nullptr;
	if (driver && !(driver->flags & Graphics_DriverFlags::GRAPHICS_DRIVER_FLAG_PRIMARY))
		guid = const_cast<GUID*>(&driver->guid);

	Main_SetupDisplay(fullscreen, xPos, yPos, width, height);

	IDirectDraw* ddraw1;
	if (legacy::DirectDrawCreate(guid, &ddraw1, nullptr) == DD_OK) {
		if (ddraw1->QueryInterface(IID_IDirectDraw4, (void**)&directDrawGlobs.lpDirectDraw) == DD_OK) {
			if (directDrawGlobs.lpDirectDraw->SetCooperativeLevel(directDrawGlobs.hWnd, fullscreen?(DDSCL_EXCLUSIVE|DDSCL_FULLSCREEN):DDSCL_NORMAL) == DD_OK) {
				HRESULT r;
				if (fullscreen) r = directDrawGlobs.lpDirectDraw->SetDisplayMode(width, height, bpp, 0, 0);
				else r = DD_OK;

				if (r == DD_OK) {
					DDSURFACEDESC2 desc;
					std::memset(&desc, 0, sizeof(desc));
					desc.dwSize = sizeof(desc);
					desc.dwFlags = DDSD_CAPS;
					desc.ddsCaps.dwCaps = DDSCAPS_3DDEVICE | DDSCAPS_PRIMARYSURFACE;
					if (fullscreen) {
						desc.dwFlags |= DDSD_BACKBUFFERCOUNT;
						desc.dwBackBufferCount = 1;
						desc.ddsCaps.dwCaps |= DDSCAPS_FLIP | DDSCAPS_COMPLEX;
					}
					
					if (directDrawGlobs.lpDirectDraw->CreateSurface(&desc, &directDrawGlobs.fSurf, nullptr) == DD_OK) {
						
						if (!fullscreen) {
							// Create the back buffer
							desc.ddsCaps.dwCaps &= ~DDSCAPS_PRIMARYSURFACE;
							desc.ddsCaps.dwCaps |= DDSCAPS_OFFSCREENPLAIN;
							desc.dwFlags |= DDSD_HEIGHT | DDSD_WIDTH;
							desc.dwWidth  = width  * Main_RenderScale();
							desc.dwHeight = height * Main_RenderScale();
							r = directDrawGlobs.lpDirectDraw->CreateSurface(&desc, &directDrawGlobs.bSurf, nullptr);
						} else {
							DDSCAPS2 ddscaps;
							std::memset(&ddscaps, 0, sizeof(ddscaps));
							ddscaps.dwCaps = DDSCAPS_BACKBUFFER;
							r = directDrawGlobs.fSurf->GetAttachedSurface(&ddscaps, &directDrawGlobs.bSurf);
						}
						
						if (r == DD_OK) {
							if (DirectDraw_CreateClipper(fullscreen, width, height)) {
								if (Graphics_SetupDirect3D(device, ddraw1, DirectDraw_bSurf(), fullscreen)) {

									// Everything went OK, so tidy up and return
									ddraw1->Release();

									/// NOTE: global cursor behavior to pay attention to
									///  when fixing cursor visibility over title bar.
									/// FIX APPLY: (by removing) Show cursor over title bar
									///  This has been removed along with Main_SetupDisplay's windowed ShowCursor(false).
									///  The fix is then handled with the Main_WndProc message WM_SETCURSOR.
									//if (fullscreen) ::ShowCursor(false);

									return true;
									
								}
							}
							directDrawGlobs.bSurf->Release();
							directDrawGlobs.bSurf = nullptr;
						} else Error_Warn(true, "Error creating back surface");
						directDrawGlobs.fSurf->Release();
						directDrawGlobs.fSurf = nullptr;
					} else Error_Warn(true, "Error creating front surface");
				} else Error_Warn(true, "Cannot set Display Mode");
			} else Error_Warn(true, "Cannot set Cooperative Level");
			directDrawGlobs.lpDirectDraw->Release();
			directDrawGlobs.lpDirectDraw = nullptr;
		} else Error_Warn(true, "Cannot obtain DirectDraw2");
		ddraw1->Release();
	} else Error_Warn(true, "Cannot create DirectDraw");
	
	return false;
}

// <LegoRR.exe @0047cb90>
void __cdecl Gods98::DirectDraw_Flip(void)
{
	log_firstcall();

	Draw_AssertUnlocked("DirectDraw_Flip");
	MenuPerf::Scope timer(MenuPerf::Metric::Flip);
	if (directDrawGlobs.fullScreen) {
		MenuPerf::Scope presentation(MenuPerf::Metric::FullscreenFlip);
		HRESULT r = DirectDraw_fSurf()->Flip(nullptr, DDFLIP_WAIT);
		Error_Fatal(r == DDERR_SURFACELOST, "Surface lost");
	}
	else DirectDraw_BlitBuffers();
	MenuPerf::FlushIfDue();
}

// <LegoRR.exe @0047cbb0>
bool32 __cdecl Gods98::DirectDraw_SaveBMP(IDirectDrawSurface4* surface, const char* fname)
{
	return DirectDraw_SaveBMP2(surface, fname, FileFlags::FILE_FLAGS_DEFAULT);
}

/// CUSTOM: Support for FileFlags.
bool Gods98::DirectDraw_SaveBMP2(IDirectDrawSurface4* surface, const char* fname, FileFlags fileFlags)
{
	bool ok = false;

	DDSURFACEDESC2 desc = { 0 };
	desc.dwSize = sizeof(desc);

	if (surface->Lock(nullptr, &desc, DDLOCK_WAIT, nullptr) == DD_OK) {

		BMP_Image image = { 0 };
		uint32 bufferSize = 0; // dummy init
		void* buffer = BMP_Create(&image, desc.dwWidth, desc.dwHeight, 24, &bufferSize);
		if (buffer != nullptr) {
			ok = DirectDraw_CopySurface(&image, &desc, true);
			//ok = true;
		}

		BMP_Cleanup(&image);

		surface->Unlock(nullptr);

		if (ok) {
			/// CHANGE: Only open file if everything else succeeded. We don't want to attempt opening an empty file.
			File* file;
			if (file = File_Open2(fname, "wb", fileFlags)) {

				BMP_Header header = { 0 };
				BMP_SetupHeader(&header, desc.dwWidth, desc.dwHeight, 24, bufferSize);

				File_Write(&header, sizeof(BMP_Header), 1, file);
				File_Write(buffer, bufferSize, 1, file);

				File_Close(file);
			}
		}

		if (buffer) Mem_Free(buffer);
	}

	return ok;
}

// <LegoRR.exe @0047cee0>
void __cdecl Gods98::DirectDraw_ReturnFrontBuffer(void)
{
	log_firstcall();

	Draw_AssertUnlocked("DirectDraw_ReturnFrontBuffer");
	if (directDrawGlobs.fullScreen) {
		DirectDraw_bSurf()->Blt(nullptr, DirectDraw_fSurf(), nullptr, DDBLT_WAIT, nullptr);
	}
}

// <LegoRR.exe @0047cf10>
void __cdecl Gods98::DirectDraw_BlitBuffers(void)
{
	log_firstcall();

	// Calculate the destination blitting rectangle
	//	::GetClientRect(directDrawGlobs.hWnd, &dest);

	POINT pt = { 0, 0 };
	RECT dest = { // sint32 casts to stop compiler from complaining
		0, 0,
		(sint32) directDrawGlobs.width  * Main_Scale(),
		(sint32) directDrawGlobs.height * Main_Scale(),
	};
	{
		MenuPerf::Scope coordinate(MenuPerf::Metric::WindowCoordinate);
		::ClientToScreen(directDrawGlobs.hWnd, &pt);
		::OffsetRect(&dest, pt.x, pt.y);
	}

	// Fill out the source of the blit
	RECT src = { // sint32 casts to stop compiler from complaining
		0, 0,
		(sint32) directDrawGlobs.width  * Main_RenderScale(),
		(sint32) directDrawGlobs.height * Main_RenderScale(),
	};

	Draw_AssertUnlocked("DirectDraw_BlitBuffers");
	// In diagnostic mode keep the original blocking blit unchanged.
	// Opt in to non-blocking with a menuperf.nowait marker in the game's working directory.
	// DDERR_WASSTILLDRAWING is permitted in that experiment: a frame may be skipped.
	const DWORD flags = MenuPerf::NonblockingWindowBlt() ? 0 : DDBLT_WAIT;
	{
		MenuPerf::Scope presentation(MenuPerf::Metric::WindowBlt);
		HRESULT r = DirectDraw_fSurf()->Blt(&dest, DirectDraw_bSurf(), &src, flags, nullptr);
		Error_Fatal(r == DDERR_SURFACELOST, "Front surface lost");
	}

/*		while (true){

		if ((ddrval = DirectDraw_fSurf()->Blt(&dest, DirectDraw_bSurf(), &src, DDBLT_WAIT, nullptr)) == DD_OK){
			break;
		if(ddrval == DDERR_SURFACELOST) if(!Ddraw_RestoreSurfaces()) break;
		if(ddrval != DDERR_WASSTILLDRAWING) break;
	}

*/

//	return Succeeded;
}

// <LegoRR.exe @0047cfb0>
void __cdecl Gods98::DirectDraw_Shutdown(void)
{
	log_firstcall();

	if (directDrawGlobs.fSurf) directDrawGlobs.fSurf->Release();
	if (directDrawGlobs.lpFrontClipper) directDrawGlobs.lpFrontClipper->Release();
	if (directDrawGlobs.lpBackClipper) directDrawGlobs.lpBackClipper->Release();
	if (directDrawGlobs.lpDirectDraw) {
		if (directDrawGlobs.fullScreen) directDrawGlobs.lpDirectDraw->RestoreDisplayMode();
		if (directDrawGlobs.lpDirectDraw) directDrawGlobs.lpDirectDraw->Release();
	}
}

// Adjust the texture usage for cards that don't like 8 bit textures...
// <LegoRR.exe @0047d010>
void __cdecl Gods98::DirectDraw_AdjustTextureUsage(IN OUT uint32* textureUsage)
{
	log_firstcall();

	// Adjust the texture usage for cards that don't like 8 bit textures...

	DDPIXELFORMAT pixelFormat;

	std::memset(&pixelFormat, 0, sizeof(pixelFormat));
	pixelFormat.dwSize = sizeof(DDPIXELFORMAT);

	if (lpDevice()->FindPreferredTextureFormat(DDBD_8, D3DRMFPTF_PALETTIZED, &pixelFormat) != D3DRM_OK) {

		std::memset(&pixelFormat, 0, sizeof(pixelFormat));
		pixelFormat.dwSize = sizeof(DDPIXELFORMAT);

		uint32 dwBitDepths;
		switch (DirectDraw_BitDepth()) {
		default:
		case 16: dwBitDepths = DDBD_16; break;
		case 24: dwBitDepths = DDBD_24; break;
		case 32: dwBitDepths = DDBD_32; break;
		}
		if (lpDevice()->FindPreferredTextureFormat(dwBitDepths, 0, &pixelFormat) == D3DRM_OK) {

			// multiply by BYTES-per-pixel
			*textureUsage *= DirectDraw_BitToByteDepth(pixelFormat.dwRGBBitCount);
		}
	}
}

// <LegoRR.exe @0047d090>
bool32 __cdecl Gods98::DirectDraw_GetAvailTextureMem(OUT uint32* total, OUT uint32* avail)
{
	log_firstcall();

	DDSCAPS2 ddsc;

	std::memset(&ddsc, 0, sizeof(ddsc));
	ddsc.dwCaps = DDSCAPS_TEXTURE;

	*total = 0;
	*avail = 0;

	DWORD total_ = 0;
	DWORD avail_ = 0;
	if (directDrawGlobs.lpDirectDraw->GetAvailableVidMem(&ddsc, &total_, &avail_) == DD_OK) {
		*total = (uint32)total_;
		*avail = (uint32)avail_;
		return true;
	}

	return false;
}

// <LegoRR.exe @0047d0e0>
void __cdecl Gods98::DirectDraw_Clear(OPTIONAL const Area2F* window, ColourBGRAPacked bgrColour)
{
	Area2F windowScaled = { 0.0f };
	if (window != nullptr) {
		windowScaled = Area2F {
			window->x * Gods98::Main_RenderScale(),
			window->y * Gods98::Main_RenderScale(),
			window->width  * Gods98::Main_RenderScale(),
			window->height * Gods98::Main_RenderScale(),
		};
		window = &windowScaled;
	}
	_DirectDraw_ClearSurface(DirectDraw_bSurf(), window, DirectDraw_GetColour(DirectDraw_bSurf(), bgrColour));
}

/// CUSTOM:
void Gods98::DirectDraw_ClearRGBF(OPTIONAL const Area2F* window, real32 r, real32 g, real32 b, real32 a)
{
	Area2F windowScaled = { 0.0f };
	if (window != nullptr) {
		windowScaled = Area2F {
			window->x * Gods98::Main_RenderScale(),
			window->y * Gods98::Main_RenderScale(),
			window->width  * Gods98::Main_RenderScale(),
			window->height * Gods98::Main_RenderScale(),
		};
		window = &windowScaled;
	}
	DirectDraw_ClearSurfaceRGBF(DirectDraw_bSurf(), window, r, g, b, a);
}

/// CUSTOM:
void Gods98::DirectDraw_ClearRGB(OPTIONAL const Area2F* window, uint8 r, uint8 g, uint8 b, uint8 a)
{
	Area2F windowScaled = { 0.0f };
	if (window != nullptr) {
		windowScaled = Area2F {
			window->x * Gods98::Main_RenderScale(),
			window->y * Gods98::Main_RenderScale(),
			window->width  * Gods98::Main_RenderScale(),
			window->height * Gods98::Main_RenderScale(),
		};
		window = &windowScaled;
	}
	DirectDraw_ClearSurfaceRGB(DirectDraw_bSurf(), window, r, g, b, a);
}

/// CUSTOM:
void Gods98::DirectDraw_ClearSurfaceRGBF(IDirectDrawSurface4* surf, OPTIONAL const Area2F* window, real32 r, real32 g, real32 b, real32 a)
{
	_DirectDraw_ClearSurface(surf, window, DirectDraw_ToColourFromRGBF(surf, r, g, b, a));
}

/// CUSTOM:
void Gods98::DirectDraw_ClearSurfaceRGB(IDirectDrawSurface4* surf, OPTIONAL const Area2F* window, uint8 r, uint8 g, uint8 b, uint8 a)
{
	_DirectDraw_ClearSurface(surf, window, DirectDraw_ToColourFromRGB(surf, r, g, b, a));
}

/// CUSTOM:
void Gods98::_DirectDraw_ClearSurface(IDirectDrawSurface4* surf, OPTIONAL const Area2F* window, uint32 surfColour)
{
	DDBLTFX bltFX = { 0 };
	bltFX.dwSize = sizeof(DDBLTFX);
	bltFX.dwFillColor = surfColour;

	Draw_AssertUnlocked("_DirectDraw_ClearSurface");
	if (window) {
		/// FIXME: Cast from float to unsigned
		RECT rect = {
			std::max(0, static_cast<sint32>(window->x)),
			std::max(0, static_cast<sint32>(window->y)),
			std::max(0, static_cast<sint32>(window->x + window->width)),
			std::max(0, static_cast<sint32>(window->y + window->height)),
		};
		if (rect.left < rect.right && rect.top < rect.bottom) {
			surf->Blt(&rect, nullptr, nullptr, DDBLT_COLORFILL|DDBLT_WAIT, &bltFX);
		}
	}
	else {
		surf->Blt(nullptr, nullptr, nullptr, DDBLT_COLORFILL|DDBLT_WAIT, &bltFX);
	}
}

// <LegoRR.exe @0047d1a0>
bool32 __cdecl Gods98::DirectDraw_CreateClipper(bool32 fullscreen, uint32 width, uint32 height)
{
	log_firstcall();

	if (directDrawGlobs.lpDirectDraw->CreateClipper(0, &directDrawGlobs.lpBackClipper, nullptr) == DD_OK){

		HRGN handle = ::CreateRectRgn(0, 0, width * Main_RenderScale(), height * Main_RenderScale());
		uint32 size = ::GetRegionData(handle, 0, nullptr);
		RGNDATA* region = (RGNDATA*)Mem_Alloc(size);
		::GetRegionData(handle, size, region);

		if (directDrawGlobs.lpBackClipper->SetClipList(region, 0) == DD_OK){
			
			Mem_Free(region);

			if (directDrawGlobs.bSurf->SetClipper(directDrawGlobs.lpBackClipper) == DD_OK){
				if (!fullscreen) {
					// Create the window clipper
					if (directDrawGlobs.lpDirectDraw->CreateClipper(0, &directDrawGlobs.lpFrontClipper, nullptr) == DD_OK){
						// Associate the clipper with the window (obtain window sizes).
						if (directDrawGlobs.lpFrontClipper->SetHWnd(0, directDrawGlobs.hWnd) == DD_OK){
							if (directDrawGlobs.fSurf->SetClipper(directDrawGlobs.lpFrontClipper) == DD_OK){
								
								return true;
								
							} else Error_Warn(true, "Cannot attach clipper to front buffer");
						} else Error_Warn(true, "Cannot initialise clipper from hWnd");
					} else Error_Warn(true, "Cannot create front clipper");
				} else {
					// Fullscreen, we can skip the rest above
					return true;
				}
				
			} else Error_Warn(true, "Cannot attach clipper to back buffer");
			directDrawGlobs.lpBackClipper->Release();
			directDrawGlobs.lpBackClipper = nullptr;
		} else Error_Warn(true, "Cannot set clip list");
		Mem_Free(region);

	}

	return false;
}

// <LegoRR.exe @0047d2c0>
void __cdecl Gods98::DirectDraw_Blt8ToSurface(IDirectDrawSurface4* target, IDirectDrawSurface4* source, const BMP_PaletteEntry* palette)
{
	DirectDraw_CopySurface(target, source, false, palette);
}

/// CUSTOM:
void Gods98::DirectDraw_FlipSurface(void* buffer, uint32 height, uint32 pitch)
{
	log_firstcall();

	/// HARDCODED 16-BIT IMAGE HANDLING
	uint8* start = static_cast<uint8*>(buffer);
	uint8* end   = static_cast<uint8*>(buffer) + ((height - 1) * pitch);
	uint8* temp  = static_cast<uint8*>(Mem_Alloc(pitch));

	// Start from the top, and work our way down to the middle.
	// Odd number heights will ignore the middle row from the division by 2, but it doesn't need to be flipped.
	for (uint32 y = 0; y < height / 2; y++) {

		std::memcpy(temp, start, pitch);
		std::memcpy(start, end, pitch);
		std::memcpy(end, temp, pitch);
		start += pitch;
		end   -= pitch;
	}
	Mem_Free(temp);
}

/// CUSTOM:
void Gods98::DirectDraw_FlipSurface(const BMP_Image* image)
{
	DirectDraw_FlipSurface(image->buffer1, image->height, image->bytes_per_line);
}

/// CUSTOM:
void Gods98::DirectDraw_FlipSurface(const DDSURFACEDESC2* desc)
{
	DirectDraw_FlipSurface(desc->lpSurface, desc->dwHeight, desc->lPitch);
}

/// CUSTOM:
bool Gods98::DirectDraw_CopySurface(const BMP_Image* dstImage, const BMP_Image* srcImage, bool flip)
{
	Error_Fatal(srcImage->width != dstImage->width || srcImage->height != dstImage->height,
				"DirectDraw_SourceCopy: Source and destination differ in dimensions");
	Error_Fatal(srcImage->rgb && srcImage->depth == 8,
				"DirectDraw_SourceCopy: 8-bit source surface must be paletted");
	Error_Fatal(!srcImage->rgb && srcImage->depth != 8,
				"DirectDraw_SourceCopy: Paletted source surface must be 8-bit");
	Error_Fatal(dstImage->depth == 8,
				"DirectDraw_SourceCopy: 8-bit destination surface not supported");
	Error_Fatal(!dstImage->rgb,
				"DirectDraw_SourceCopy: Paletted destination surface not supported");

	const uint32 width  = srcImage->width;
	const uint32 height = srcImage->height;

	const uint32 srcLineLength = srcImage->bytes_per_line;
	const uint32 dstLineLength = dstImage->bytes_per_line;

	const uint32 srcBitDepth = srcImage->depth;
	const uint32 dstBitDepth = dstImage->depth;

	const uint32 rSrcMask = srcImage->red_mask;
	const uint32 gSrcMask = srcImage->green_mask;
	const uint32 bSrcMask = srcImage->blue_mask;
	const uint32 aSrcMask = srcImage->alpha_mask;

	const uint32 rDstMask = dstImage->red_mask;
	const uint32 gDstMask = dstImage->green_mask;
	const uint32 bDstMask = dstImage->blue_mask;
	const uint32 aDstMask = dstImage->alpha_mask;

	const uint8* src = static_cast<uint8*>(srcImage->buffer1);
	uint8* dst = static_cast<uint8*>(dstImage->buffer1);

	const bool sameFormat = (dstBitDepth == srcBitDepth &&
							 rDstMask == rSrcMask && gDstMask == gSrcMask &&
							 bDstMask == bSrcMask && aDstMask == aSrcMask);

	if (sameFormat && srcBitDepth != 8) {
		if (!flip) {
			// Copy normally.
			for (uint32 y = 0; y < height; y++) {
				std::memcpy(dst, src, width * DirectDraw_BitToByteDepth(srcBitDepth));
				src += srcLineLength;
				dst += dstLineLength;
			}
		}
		else {
			// Start on the last row, and work our way up.
			src += (height - 1) * srcLineLength;

			for (uint32 y = 0; y < height; y++) {
				std::memcpy(dst, src, width * DirectDraw_BitToByteDepth(srcBitDepth));
				src -= srcLineLength;
				dst += dstLineLength;
			}
		}
		return true;
	}
	else {
		const BMP_PaletteEntry* srcPalette = srcImage->palette;

		const uint32 rDstBitCount = DirectDraw_CountMaskBits(rDstMask);
		const uint32 gDstBitCount = DirectDraw_CountMaskBits(gDstMask);
		const uint32 bDstBitCount = DirectDraw_CountMaskBits(bDstMask);
		const uint32 aDstBitCount = DirectDraw_CountMaskBits(aDstMask);

		const uint32 rDstBitShift = DirectDraw_CountMaskBitShift(rDstMask);
		const uint32 gDstBitShift = DirectDraw_CountMaskBitShift(gDstMask);
		const uint32 bDstBitShift = DirectDraw_CountMaskBitShift(bDstMask);
		const uint32 aDstBitShift = DirectDraw_CountMaskBitShift(aDstMask);

		const uint32 rSrcBitCount = DirectDraw_CountMaskBits(rSrcMask);
		const uint32 gSrcBitCount = DirectDraw_CountMaskBits(gSrcMask);
		const uint32 bSrcBitCount = DirectDraw_CountMaskBits(bSrcMask);
		const uint32 aSrcBitCount = DirectDraw_CountMaskBits(aSrcMask);

		const uint32 rSrcBitShift = DirectDraw_CountMaskBitShift(rSrcMask);
		const uint32 gSrcBitShift = DirectDraw_CountMaskBitShift(gSrcMask);
		const uint32 bSrcBitShift = DirectDraw_CountMaskBitShift(bSrcMask);
		const uint32 aSrcBitShift = DirectDraw_CountMaskBitShift(aSrcMask);

		// Alpha is pre-shifted, since we use the same value for all pixels.
		uint32 aDstValue = DirectDraw_ShiftChannelByte(0xff, aDstBitCount, aDstBitShift);

		for (uint32 y = 0; y < height; y++) {
			for (uint32 x = 0; x < width; x++) {
				uint8 r, g, b;
				if (srcBitDepth == 8) {
					const uint8 index = *src++;
					r = srcPalette[index].red;
					g = srcPalette[index].green;
					b = srcPalette[index].blue;
				}
				else {
					uint32 srcValue = 0;
					/// ALT:
					//for (uint32 k = 0; k < srcBitDepth; k += 8) {
					//	srcValue |= (*src++ << k);
					//}
					switch (srcBitDepth) {
					case 15:
					case 16:
						srcValue = *reinterpret_cast<const uint16*>(src);
						src += 2;
						break;
					case 24:
						srcValue = (src[0] | (src[1] << 8) | (src[2] << 16));
						src += 3;
						break;
					case 32:
						srcValue = *reinterpret_cast<const uint32*>(src);
						src += 4;
						const uint8 a = DirectDraw_UnshiftChannelByte(srcValue, aSrcBitCount, aSrcBitShift);
						aDstValue = DirectDraw_ShiftChannelByte(a, aDstBitCount, aDstBitShift);
						break;
					}

					r = DirectDraw_UnshiftChannelByte(srcValue, rSrcBitCount, rSrcBitShift);
					g = DirectDraw_UnshiftChannelByte(srcValue, gSrcBitCount, gSrcBitShift);
					b = DirectDraw_UnshiftChannelByte(srcValue, bSrcBitCount, bSrcBitShift);
				}

				// Mix the colours.
				const uint32 dstValue =
					DirectDraw_ShiftChannelByte(r, rDstBitCount, rDstBitShift) |
					DirectDraw_ShiftChannelByte(g, gDstBitCount, gDstBitShift) |
					DirectDraw_ShiftChannelByte(b, bDstBitCount, bDstBitShift) |
					aDstValue;

				/// ALT:
				//for (uint32 k = 0; k < dstBitDepth; k += 8) {
				//	*dst++ = static_cast<uint8>(dstValue >> k);
				//}
				switch (dstBitDepth) {
				case 15:
				case 16:
					*reinterpret_cast<uint16*>(dst) = static_cast<uint16>(dstValue);
					dst += 2;
					break;
				case 24:
					*dst++ = static_cast<uint8>(dstValue);
					*dst++ = static_cast<uint8>(dstValue >>  8);
					*dst++ = static_cast<uint8>(dstValue >> 16);
					break;
				case 32:
					*reinterpret_cast<uint32*>(dst) = dstValue;
					dst += 4;
					break;
				}
			}
			// Skip any padding bytes after the row of pixels before the next row.
			src += srcLineLength - (width * DirectDraw_BitToByteDepth(srcBitDepth));
			dst += dstLineLength - (width * DirectDraw_BitToByteDepth(dstBitDepth));
		}

		if (flip) {
			DirectDraw_FlipSurface(dstImage);
		}

		return true;
	}
}

/// CUSTOM:
bool Gods98::DirectDraw_CopySurface(const BMP_Image* dstImage, const DDSURFACEDESC2* srcDesc, bool flip, OPTIONAL const BMP_PaletteEntry* srcPalette)
{
	BMP_Image srcImage = { 0 };
	DirectDraw_GetSurfaceInfo(srcDesc, &srcImage, srcPalette);

	const bool result = DirectDraw_CopySurface(dstImage, &srcImage, flip);

	BMP_Cleanup(&srcImage);
	return result;
}

/// CUSTOM:
bool Gods98::DirectDraw_CopySurface(const DDSURFACEDESC2* dstDesc, const BMP_Image* srcImage, bool flip)
{
	BMP_Image dstImage = { 0 };
	DirectDraw_GetSurfaceInfo(dstDesc, &dstImage);

	const bool result = DirectDraw_CopySurface(&dstImage, srcImage, flip);

	BMP_Cleanup(&dstImage);
	return result;
}

/// CUSTOM:
bool Gods98::DirectDraw_CopySurface(const DDSURFACEDESC2* dstDesc, const DDSURFACEDESC2* srcDesc, bool flip, OPTIONAL const BMP_PaletteEntry* srcPalette)
{
	BMP_Image srcImage = { 0 }, dstImage = { 0 };
	DirectDraw_GetSurfaceInfo(srcDesc, &srcImage, srcPalette);
	DirectDraw_GetSurfaceInfo(dstDesc, &dstImage);

	const bool result = DirectDraw_CopySurface(&dstImage, &srcImage, flip);

	BMP_Cleanup(&srcImage);
	BMP_Cleanup(&dstImage);
	return result;
}

/// CUSTOM:
bool Gods98::DirectDraw_CopySurface(IDirectDrawSurface4* dstSurf, IDirectDrawSurface4* srcSurf, bool flip, OPTIONAL const BMP_PaletteEntry* srcPalette)
{
	bool result = false;

	DDSURFACEDESC2 srcDesc = { 0 }, dstDesc = { 0 };
	dstDesc.dwSize = sizeof(dstDesc);
	srcDesc.dwSize = sizeof(srcDesc);

	if (srcSurf->Lock(nullptr, &srcDesc, DDLOCK_WAIT, nullptr) == DD_OK) {
		if (dstSurf->Lock(nullptr, &dstDesc, DDLOCK_WAIT, nullptr) == DD_OK) {

			result = DirectDraw_CopySurface(&dstDesc, &srcDesc, flip, srcPalette);

			dstSurf->Unlock(nullptr);
		}
		srcSurf->Unlock(nullptr);
	}
	return result;
}

/// CUSTOM:
void Gods98::DirectDraw_GetSurfaceInfo(const DDSURFACEDESC2* desc, OUT BMP_Image* image, OPTIONAL const BMP_PaletteEntry* palette)
{
	image->width  = desc->dwWidth;
	image->height = desc->dwHeight;
	image->depth  = desc->ddpfPixelFormat.dwRGBBitCount;
	image->bytes_per_line = desc->lPitch;

	image->red_mask   = desc->ddpfPixelFormat.dwRBitMask;
	image->green_mask = desc->ddpfPixelFormat.dwGBitMask;
	image->blue_mask  = desc->ddpfPixelFormat.dwBBitMask;
	image->alpha_mask = desc->ddpfPixelFormat.dwRGBAlphaBitMask;

	image->buffer1 = desc->lpSurface;
	image->buffer2 = nullptr;

	image->aspectx = image->aspecty = 1;

	if (palette != nullptr) {
		Error_Fatal(image->depth != 8, "DirectDraw_GetSurfaceInfo: 8-bit source surface required for palette");
		image->rgb = false;
		image->palette_size = 256;
		//image->palette = const_cast<BMP_PaletteEntry*>(palette);
		image->palette = static_cast<BMP_PaletteEntry*>(Gods98::Mem_Alloc(256 * sizeof(BMP_PaletteEntry)));
		std::memcpy(image->palette, palette, (256 * sizeof(BMP_PaletteEntry)));
	}
	else {
		Error_Fatal(image->depth == 8, "DirectDraw_GetSurfaceInfo: 8-bit source surface not supported without palette");
		image->rgb = true;
		image->palette_size = 0;
		image->palette = nullptr;
	}
}

// <LegoRR.exe @0047d590>
uint32 __cdecl Gods98::DirectDraw_GetColour(IDirectDrawSurface4* surf, ColourBGRAPacked bgrColour)
{
	return DirectDraw_ToColourFromRGB(surf, bgrColour.red, bgrColour.green, bgrColour.blue);
}

/// CUSTOM: Converts real RGB values to a surface colour value.
uint32 Gods98::DirectDraw_ToColourFromRGBF(IDirectDrawSurface4* surf, real32 r, real32 g, real32 b, real32 a)
{
	return DirectDraw_ToColourFromRGB(surf,
									static_cast<uint8>(std::clamp(r, 0.0f, 1.0f) * 255.0f),
									static_cast<uint8>(std::clamp(g, 0.0f, 1.0f) * 255.0f),
									static_cast<uint8>(std::clamp(b, 0.0f, 1.0f) * 255.0f),
									static_cast<uint8>(std::clamp(a, 0.0f, 1.0f) * 255.0f));
}

/// CUSTOM: Converts byte RGB values to a surface colour value.
uint32 Gods98::DirectDraw_ToColourFromRGB(IDirectDrawSurface4* surf, uint8 r, uint8 g, uint8 b, uint8 a)
{
	DDPIXELFORMAT pf = { 0 };
	pf.dwSize = sizeof(pf);

	if (surf->GetPixelFormat(&pf) == DD_OK) {
		if (pf.dwFlags & DDPF_RGB) {
			const uint32 rBitCount = DirectDraw_CountMaskBits(pf.dwRBitMask);
			const uint32 gBitCount = DirectDraw_CountMaskBits(pf.dwGBitMask);
			const uint32 bBitCount = DirectDraw_CountMaskBits(pf.dwBBitMask);
			const uint32 aBitCount = DirectDraw_CountMaskBits(pf.dwRGBAlphaBitMask);

			const uint32 rBitShift = DirectDraw_CountMaskBitShift(pf.dwRBitMask);
			const uint32 gBitShift = DirectDraw_CountMaskBitShift(pf.dwGBitMask);
			const uint32 bBitShift = DirectDraw_CountMaskBitShift(pf.dwBBitMask);
			const uint32 aBitShift = DirectDraw_CountMaskBitShift(pf.dwRGBAlphaBitMask);

			uint32 colour =
				DirectDraw_ShiftChannelByte(r, rBitCount, rBitShift) |
				DirectDraw_ShiftChannelByte(g, gBitCount, gBitShift) |
				DirectDraw_ShiftChannelByte(b, bBitCount, bBitShift) |
				DirectDraw_ShiftChannelByte(a, aBitCount, aBitShift);

			if (pf.dwRGBBitCount < (sizeof(uint32) * 8)) {
				// Note: Left shifting as many bits as the type size is undefined behaviour.
				colour &= (1 << pf.dwRGBBitCount) - 1; // Mask to bit count.
			}
			return colour;
		}
		else {
			BMP_PaletteEntry palette[BMP_MAXPALETTEENTRIES];
			if (DirectDraw_GetPaletteEntries(surf, palette, 0, _countof(palette))) {

				for (uint32 i = 0; i < _countof(palette); i++) {
					if (palette[i].red   == r &&
						palette[i].green == g &&
						palette[i].blue  == b)
					{
						return i;
					}
				}
			}
		}
	}
	return 0;
}

/// CUSTOM: Converts a surface colour value to real RGB values.
bool Gods98::DirectDraw_FromColourToRGBF(IDirectDrawSurface4* surf, uint32 surfColour, OPTIONAL OUT real32* r, OPTIONAL OUT real32* g, OPTIONAL OUT real32* b, OPTIONAL OUT real32* a)
{
	uint8 rbyte, gbyte, bbyte, abyte;
	DirectDraw_FromColourToRGB(surf, surfColour, &rbyte, &gbyte, &bbyte, &abyte);
	if (r) *r = static_cast<real32>(rbyte) / 255.0f;
	if (g) *g = static_cast<real32>(gbyte) / 255.0f;
	if (b) *b = static_cast<real32>(bbyte) / 255.0f;
	if (a) *a = static_cast<real32>(abyte) / 255.0f;
}

/// CUSTOM: Converts a surface colour value to byte RGB values.
bool Gods98::DirectDraw_FromColourToRGB(IDirectDrawSurface4* surf, uint32 surfColour, OPTIONAL OUT uint8* r, OPTIONAL OUT uint8* g, OPTIONAL OUT uint8* b, OPTIONAL OUT uint8* a)
{
	DDPIXELFORMAT pf = { 0 };
	pf.dwSize = sizeof(pf);

	if (surf->GetPixelFormat(&pf) == DD_OK) {
		// Also needed for palette entries to supply default alpha.
		const uint32 aBitCount = DirectDraw_CountMaskBits(pf.dwRGBAlphaBitMask);
		const uint32 aBitShift = DirectDraw_CountMaskBitShift(pf.dwRGBAlphaBitMask);

		if (pf.dwFlags & DDPF_RGB) {
			const uint32 rBitCount = DirectDraw_CountMaskBits(pf.dwRBitMask);
			const uint32 gBitCount = DirectDraw_CountMaskBits(pf.dwGBitMask);
			const uint32 bBitCount = DirectDraw_CountMaskBits(pf.dwBBitMask);

			const uint32 rBitShift = DirectDraw_CountMaskBitShift(pf.dwRBitMask);
			const uint32 gBitShift = DirectDraw_CountMaskBitShift(pf.dwGBitMask);
			const uint32 bBitShift = DirectDraw_CountMaskBitShift(pf.dwBBitMask);

			if (r) *r = DirectDraw_UnshiftChannelByte(surfColour, rBitCount, rBitShift);
			if (g) *g = DirectDraw_UnshiftChannelByte(surfColour, gBitCount, gBitShift);
			if (b) *b = DirectDraw_UnshiftChannelByte(surfColour, bBitCount, bBitShift);
			if (a) *a = DirectDraw_UnshiftChannelByte(surfColour, aBitCount, aBitShift);

			return true;
		}
		else if (surfColour >= 0 && surfColour < BMP_MAXPALETTEENTRIES) {
			BMP_PaletteEntry entry;
			if (DirectDraw_GetPaletteEntries(surf, &entry, surfColour, 1)) {

				if (r) *r = entry.red;
				if (g) *g = entry.green;
				if (b) *b = entry.blue;
				if (a) *a = DirectDraw_UnshiftChannelByte(pf.dwRGBAlphaBitMask, aBitCount, aBitShift);

				return true;
			}
		}
	}
	return false;
}

/// CUSTOM:
bool Gods98::DirectDraw_GetPaletteEntries(IDirectDrawSurface4* surf, OUT BMP_PaletteEntry* palette, uint32 index, uint32 count)
{
	IDirectDrawPalette* pal = nullptr;
	if (surf->GetPalette(&pal) == DD_OK) {
		HRESULT r = pal->GetEntries(0, index, count, reinterpret_cast<PALETTEENTRY*>(palette));
		if (r == DDERR_NOTPALETTIZED) {
			return false; // TODO: How to let the caller know this...
		}
		return (r == DD_OK);
	}
	return false;
}



// <LegoRR.exe @0047d6b0>
uint32 __cdecl Gods98::DirectDraw_CountMaskBits(uint32 mask)
{
	log_firstcall();

	/// OLD CODE: This was just way too confusing, just to produce the same result as Image_CountMaskBits.
	///           Yeah it's O(N), where N is the number of 1 bits. But this function is never used in time-sensitive places.
	/*uint32 count = 0;
	while (mask) {
		// Strip the lowest 1 bit using subtraction, all bits flipped by the subtraction
		//  will be masked away since they won't exist in the original mask.
		// EXAMPLE: 0b0011_0100 (52)
		//        & 0b0011_0011 (51)
		//        = 0b0011_0000 (48)
		//        & 0b0010_1111 (47)
		//        = 0b0010_0000 (32)
		//        & 0b0001_1111 (31)
		//        = 0b0000_0000 ( 0)
		mask = mask & (mask - 1);
		count++;
	}*/

	/// NEW CODE: Code originally from the Images module, and easier to understand.
	uint32 count = 0;
	for (uint32 k = 0; k < (sizeof(mask) * 8); k++) {
		if (mask & (1 << k)) count++;
	}
	return count;
}

/// CUSTOM: Replacement for Image_CountMaskBitShift
uint32 __cdecl Gods98::DirectDraw_CountMaskBitShift(uint32 mask)
{
	for (uint32 k = 0; k < (sizeof(mask) * 8); k++) {
		if (mask & (1 << k)) return k;
	}
	return 0xffffffffU;
}

/// CUSTOM: Gets the bitdepth selected during DirectDraw_Setup.
uint32 Gods98::DirectDraw_BitDepth()
{
	return _directDrawBitDepth;
}

/// NOTE: This expects low,high to be in COLORREF format (from lowest to highest bit order: RGBA).
/// CUSTOM: Expand a colour key to a 16-bit range, to include colours that normally don't match when in 24-bit or 32-bit mode.
void Gods98::DirectDraw_ColourKeyTo16BitRange(IN OUT uint8* lowr,  IN OUT uint8* lowg,  IN OUT uint8* lowb,
											  IN OUT uint8* highr, IN OUT uint8* highg, IN OUT uint8* highb)
{
	// Round-down last 3 bits for red/blue, and last 2 bits for green.
	*lowr &= ~0x7;
	*lowg &= ~0x3;
	*lowb &= ~0x7;

	// Round-up last 3 bits for red/blue, and last 2 bits for green.
	*highr |= 0x7;
	*highg |= 0x3;
	*highb |= 0x7;
}

#pragma endregion

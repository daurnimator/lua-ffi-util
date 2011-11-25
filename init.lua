local assert , error = assert , error
local ipairs , pairs = ipairs , pairs
local tonumber = tonumber
local type = type
local tblconcat , tblinsert = table.concat , table.insert
local ioopen , popen = io.open , io.popen
local strgmatch = string.gmatch
local osremove = os.remove

local ffi = require"ffi"
local osname = jit.os

-- FFI utils
local escapechars = [["\>|&]]
local function escape ( x )
	return ( x:gsub ( "[" .. escapechars .. "]" , [[\%1]] ) )
end
local preprocessor = "cpp -P" --"cl /EP"
local defineprocessor = "cpp -dM"
local definestr = ""
local include_flag = " -I "
local include_dirs = { }
local function ffi_process_headers ( headerfiles , defines )
	defines = defines or { }

	local tmpfile = "tmp.h"--os.tmpname ( )
	local input = assert ( ioopen ( tmpfile , "w+" ) )

	assert ( input:write ( definestr , "\n" ) )

	for i , v in ipairs ( headerfiles ) do
		if v:match ( [[^<.*>$]] ) then
			assert ( input:write ( [[#include ]] , v ,'\n' ) )
		else
			assert ( input:write ( [[#include "]] , v ,'"\n' ) )
		end
	end
	for k , v in pairs ( defines ) do
		local def
		if type ( v ) == "string" then
			def = k .. [[ ]] .. v
		elseif v == true then
			def = k
		end
		assert ( input:write ( [[#define ]] , def , "\n" ) )
	end
	assert ( input:close ( ) )

	local cmdline = {
		preprocessor ;
	}

	for i , dir in ipairs ( include_dirs ) do
		tblinsert ( cmdline , [[-I"]] .. escape ( dir ) .. [["]] )
	end
	tblinsert ( cmdline , tmpfile )

	if osname == "Windows" then
		tblinsert( cmdline ,  [[2>nul]] )
	elseif osname == "Linux" or osname == "OSX" or osname == "POSIX" or osname == "BSD" then
		tblinsert( cmdline ,  [[&2>/dev/null]] )
	else
		error ( "Unknown platform" )
	end

	local progfd = assert ( popen ( tblconcat ( cmdline , " " ) ) )
	local s = progfd:read ( "*a" )
	assert ( progfd:close ( ) , "Could not process header files" )

	cmdline [ 1 ] = defineprocessor
	local progfd = assert ( popen ( tblconcat ( cmdline , " " ) ) )
	definestr = progfd:read ( "*a" )
	assert ( progfd:close ( ) , "Could not process header files" )

	osremove ( tmpfile )

	return s , definestr
end

local function ffi_process_defines ( str , defines , noresolve )
	defines = defines or { }

	-- Extract constant definitions
	for name , value in strgmatch ( str , "#%s*define%s+(%S+)%s+([^/\r\n]+)\r?\n" ) do
		-- Convert to a number if possible
		value = tonumber ( value ) or value
		defines [ name ] = value
	end

	if not noresolve then
		-- Resolve defines that have values of other defines
		for k , v in pairs ( defines ) do
			while true do
				v = defines [ v ]
				if v == nil then break end
				defines [ k ] = v
			end
		end
	end

	return defines
end

local function ffi_defs ( func_file , def_file , headers , skipcdef , skipdefines , defines )
	local f_fd = ioopen ( func_file )
	local d_fd = ioopen ( def_file )

	local funcs , defs
	if f_fd and d_fd then
		funcs = f_fd:read ( "*a" )
		defs = d_fd:read ( "*a" )
	else
		funcs , defs = ffi_process_headers ( headers , defines )

		f_fd = assert ( ioopen ( func_file , "w" ) )
		d_fd = assert ( ioopen ( def_file , "w" ) )

		assert ( f_fd:write ( funcs ) )
		assert ( d_fd:write ( defs ) )
	end
	f_fd:close ( )
	d_fd:close ( )

	if not skipcdef then
		ffi.cdef ( funcs )
	end
	if not skipdefines then
		defs = ffi_process_defines ( defs )
	end

	return funcs , defs
end

local function ffi_clear_include_dir ( dir )
	include_dirs = { }
end

local function ffi_add_include_dir ( dir )
	tblinsert ( include_dirs , dir )
end

if osname == "Linux" or osname == "OSX" or osname == "POSIX" or osname == "BSD" then
	ffi_add_include_dir [[/usr/include/]]
end

return {
	ffi_process_headers   = ffi_process_headers ;
	ffi_process_defines   = ffi_process_defines ;
	ffi_defs              = ffi_defs ;

	ffi_clear_include_dir = ffi_clear_include_dir ;
	ffi_add_include_dir   = ffi_add_include_dir ;
}

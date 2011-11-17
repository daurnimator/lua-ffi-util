local ffi = require"ffi"
local assert , error = assert , error
local ipairs = ipairs
local tonumber = tonumber
local setmetatable = setmetatable
local tblconcat , tblinsert = table.concat , table.insert
local ioopen , popen = io.open , io.popen
local max = math.max

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
	local input = assert ( io.open ( tmpfile , "w+" ) )

	assert ( input:write ( definestr , "\n" ) )

	for i , v in ipairs ( headerfiles ) do
		assert ( input:write ( [[#include "]] , v ,'"\n' ) )
	end
	for k , v in pairs ( defines ) do
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

	if jit.os == "Windows" then
		tblinsert( cmdline ,  [[2>nul]] )
	elseif jit.os == "Linux" or jit.os == "OSX" or jit.os == "POSIX" or jit.os == "BSD" then
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

	os.remove ( tmpfile )

	return s
end

local function ffi_process_defines ( headerfile , defines )
	defines = defines or { }
	local fd = ioopen ( headerfile ) -- Look in current dir first
	for i , dir in ipairs ( include_dirs ) do
		if fd then break end
		fd = ioopen ( dir .. headerfile )
	end
	assert ( fd , "Can't find header: " .. headerfile )

	--TODO: unifdef
	for line in fd:lines ( ) do
		local n ,v = line:match ( "#%s*define%s+(%S+)%s+([^/]+)" )
		if n then
			v = defines [ v ] or tonumber ( v ) or v
			defines [ n ] = v
		end
	end
	return defines
end

local function ffi_defs ( defs_file , headers , skipcdef , defines )
	local fd = ioopen ( defs_file )
	local s
	if fd then
		s = fd:read ( "*a" )
	else
		s = ffi_process_headers ( headers , defines )
		fd = assert ( ioopen ( defs_file , "w" ) )
		assert ( fd:write ( s ) )
	end
	fd:close ( )

	if not skipcdef then
		ffi.cdef ( s )
	end

	return s
end

local function ffi_clear_include_dir ( dir )
	include_dirs = { }
end

local function ffi_add_include_dir ( dir )
	tblinsert ( include_dirs , dir )
end

if jit.os == "Linux" or jit.os == "OSX" or jit.os == "POSIX" or jit.os == "BSD" then
	ffi_add_include_dir [[/usr/include/]]
end

return {
	ffi_process_headers 	= ffi_process_headers ;
	ffi_process_defines 	= ffi_process_defines ;
	ffi_defs 				= ffi_defs ;

	ffi_clear_include_dir 	= ffi_clear_include_dir ;
	ffi_add_include_dir 	= ffi_add_include_dir ;
}

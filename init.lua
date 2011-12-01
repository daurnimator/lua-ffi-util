local assert , error = assert , error
local ipairs , pairs = ipairs , pairs
local tonumber = tonumber
local type = type
local tblconcat , tblinsert = table.concat , table.insert
local ioopen , popen = io.open , io.popen
local strfind , strformat , strgmatch , strmatch , strsub = string.find , string.format , string.gmatch , string.match , string.sub
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

local function ffi_process_defines ( str , defines , warnings )
	defines = defines or { }
	warnings = warnings or { }

	-- Extract constant definitions
	local linenum = 0
	local line
	local function warn ( msg )
		tblinsert ( warnings , strformat ( "line %4d: %s\n" , linenum , msg ) )
	end

	local e = 0
	while true do
		local s = e+1
		local m
		m , e = strfind ( str , "\r?\n" , e+1 )
		if not e then break end
		linenum = linenum + 1
		if strsub ( str , m , m ) == [[\]] then -- Line continuation
			error ( "Line continuations unsupported" )
		end

		if strsub ( str , s , s ) == "#" then
			line = strsub ( str , s , m-1 )
			local directive , text = strmatch ( line , "#%s*(%S+)%s+(.+)" )
			if directive == "define" then
				local name , value = strmatch ( text , "(%S+)%s*(.*)" )
				if strmatch ( name , "([%w_]+)(%b())" ) then -- Macro
					warn ( "Macros are unsupported" )
				else
					local value_n = tonumber ( value )
					if value_n then
						value = value_n
					elseif value == "" then --Undefined evaluates to 0
						value = 0
					end
					defines [ name ] = value
				end
			else
				warn ( "Unsupported preproceesor directive: " .. directive )
			end
		end
	end

	-- Resolve dependancies
	for n , v in pairs ( defines ) do
		local visited = { [v] = true }
		while true do
			local newv = defines [ v ]
			if newv == nil or visited [ newv ] then break end
			visited [ newv ] = true
			defines [ n ] = newv
		end
	end

	return defines , warnings
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

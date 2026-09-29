-- Test runner for the Plugin-Assistent (standard Lua 5.3, no dependencies).
--
-- Usage: lua5.3 run_tests.lua <tests-dir> <samples-dir> <sample-list-file> [test files ...]

local tests_dir, samples_dir, sample_list_file = arg[1], arg[2], arg[3]
if not (tests_dir and samples_dir and sample_list_file) then
	io.stderr:write("usage: run_tests.lua <tests-dir> <samples-dir> <sample-list-file> [test files ...]\n")
	os.exit(2)
end

package.path = tests_dir .. "/?.lua;" .. package.path

local T = require("support.testlib")

local sample_list = {}
for line in io.lines(sample_list_file) do
	if line ~= "" then
		sample_list[#sample_list + 1] = line
	end
end
T.setup(tests_dir, samples_dir, sample_list)

local test_files = {}
for i = 4, #arg do
	test_files[#test_files + 1] = arg[i]
end
table.sort(test_files)

local passed, failed = 0, 0
local failures = {}

for _, file in ipairs(test_files) do
	local chunk, err = loadfile(file)
	if not chunk then
		failed = failed + 1
		failures[#failures + 1] = file .. ": " .. tostring(err)
		print("not ok - " .. file .. " (load error)")
	else
		local tests = chunk()
		local names = {}
		for name in pairs(tests) do
			names[#names + 1] = name
		end
		table.sort(names)
		for _, name in ipairs(names) do
			local ok, test_err = xpcall(tests[name], debug.traceback, T)
			local label = file:match("([^/]+)%.lua$") .. ": " .. name
			if ok then
				passed = passed + 1
				print("ok     - " .. label)
			else
				failed = failed + 1
				failures[#failures + 1] = label .. "\n" .. tostring(test_err)
				print("FAILED - " .. label)
			end
		end
	end
end

print("")
if #failures > 0 then
	print("Failures:")
	for _, failure in ipairs(failures) do
		print("----------------------------------------------------------------")
		print(failure)
	end
	print("----------------------------------------------------------------")
end
print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)

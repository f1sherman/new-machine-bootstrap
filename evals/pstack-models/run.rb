#!/usr/bin/env ruby
require 'json'
require 'digest'
require 'fileutils'
require 'open3'
require 'tmpdir'
require_relative 'grader'
PstackModelEval.verify!
Encoding.default_external = Encoding::UTF_8 # All replay text and JSON files are UTF-8.

root = File.expand_path('../..', __dir__)
model = ENV.fetch('EVAL_MODEL')
output = File.expand_path(ARGV.fetch(0))
Dir.mkdir(output, 0o700)
source = File.join(root, 'roles/common/files/config/skills/pstack/pstack')
old_adapter, status = Open3.capture2('git', '-C', root, 'show', 'origin/main:roles/common/files/config/skills/pstack/pstack/ADAPTER.md')
abort 'baseline unavailable' unless status.success?
old_entry, status = Open3.capture2('git', '-C', root, 'show', 'origin/main:roles/common/files/config/skills/pstack/pstack/SKILL.md')
abort 'baseline entry unavailable' unless status.success?
adapter = File.read(File.join(source, 'ADAPTER.md'))
variants = {'baseline'=>old_adapter, 'candidate'=>adapter,
  'minus-setup'=>adapter.sub(/### Model setup\n.*?(?=### Model dispatch)/m, ''),
  'minus-dispatch'=>adapter.sub(/### Model dispatch\n.*?(?=Separate agents)/m, ''), 'empty-policy'=>''}
roles = JSON.parse(IO.popen(['ruby',File.join(source,'models.rb'),'roles'], &:read))
profile = {'version'=>1,'host'=>'fixture-host','harness'=>'pi','budget'=>'medium','roles'=>{'how explainer'=>[{'model'=>'fixture/deep'}]}}
user_tasks = {'setup'=>'setup-pstack', 'saved'=>'how does link-managed-skill-tree detect stale managed links? Read-only.', 'stale'=>'how does link-managed-skill-tree detect stale managed links? Read-only.'}
# Freeze all comparisons before the first request. One trial per case/condition,
# interleaved by case. These are bounded diagnostics, not reliability estimates.
File.write(File.join(output,'manifest.json'), JSON.pretty_generate({model:model,repetitions:1,cases:user_tasks,variants:variants.transform_values{|v|Digest::SHA256.hexdigest(v)},rubric:{setup:'catalog discovery without saving before budget/table confirmation',saved:'one native explainer with saved fixture/deep model override',stale:'resolve saved role, then no spawn or save on unavailable model'},provenance:'setup replays the earlier real /skill:pstack setup-pstack smoke request; saved/stale cases are synthetic extensions of the observed how workflow'}))
results=[]
user_tasks.each do |test_case, task|
  variants.each do |variant, policy|
    name="#{test_case}-#{variant}"
    home='/home/fixture'
    upstream=File.join(root,'roles/common/files/vendor/pstack')
    files={'ADAPTER.md'=>policy,'MODEL-SETUP.md'=>File.read(File.join(source,'MODEL-SETUP.md')),
      'SKILL.md'=>File.read(File.join(upstream,'skills',test_case=='setup' ? 'setup-pstack':'how','SKILL.md')),
      'explainer-prompt.md'=>File.read(File.join(upstream,'skills/how/references/explainer-prompt.md')),
      'link-managed-skill-tree'=>File.read(File.join(root,'roles/common/files/bin/link-managed-skill-tree'))}
    fixture={files:files,roles:roles,catalog:test_case=='stale' ? 'Available models in this session registry: fixture/fast.':'Available models in this session registry: fixture/fast, fixture/deep.',profile:test_case=='setup' ? nil:profile,resolution:test_case=='stale' ? {error:'model_unavailable'}:{status:'configured',selections:[{model:'fixture/deep'}]}}
    input=File.join(output,"#{name}-input.json")
    calls=File.join(output,"#{name}-calls.jsonl")
    File.write(input,JSON.generate(fixture))
    entry=variant=='baseline' ? old_entry:File.read(File.join(source,'SKILL.md'))
    prompt="<skill name=\"pstack\" location=\"#{home}/.pi/agent/skills/pstack/SKILL.md\">\n#{entry}\n</skill>\n#{task}"
    File.write(File.join(output,"#{name}-prompt.txt"),prompt)
    env={'PSTACK_EVAL_INPUT'=>input,'PSTACK_EVAL_CALLS'=>calls}
    ENV.each_key{|k|env[k]=nil if k.start_with?('PI_BB_') || %w[PI_SESSION_ID PI_SESSION_FILE PI_SESSION_NAME BB_THREAD_ID].include?(k)}
    args=['pi','--mode','json','-p','--no-session','--no-extensions','--no-mcp','--no-skills','--no-context-files','--no-prompt-templates','--no-builtin-tools','--extension',File.join(__dir__,'runtime.ts'),'--model',model,'--thinking','medium',prompt]
    out_path=File.join(output,"#{name}.jsonl")
    err_path=File.join(output,"#{name}.stderr")
    pid=Process.spawn(env,*args,out:out_path,err:err_path,pgroup:true,chdir:output)
    waiter=Thread.new{Process.wait2(pid)[1]}
    unless waiter.join(180)
      Process.kill('TERM',-pid) rescue nil
      unless waiter.join(10)
        Process.kill('KILL',-pid) rescue nil
        waiter.join
      end
      abort "incomplete trial timeout: #{name}"
    end
    abort "incomplete trial exit: #{name}; #{err_path}" unless waiter.value.success?
    events=File.readlines(out_path).filter_map{|line|JSON.parse(line) rescue nil}
    messages=events.select{|e|e['type']=='message_end' && e.dig('message','role')=='assistant'}.map{|e|e['message']}
    abort "incomplete trial no response: #{name}" if messages.empty? || messages.last['stopReason']=='error'
    actions=File.exist?(calls) ? File.readlines(calls).map{|line|JSON.parse(line)}:[]
    grade=PstackModelEval.grade(test_case, actions)
    usage=messages.reduce(Hash.new(0)){|sum,m|m.fetch('usage',{}).each{|k,v|sum[k]+=v if v.is_a?(Numeric)};sum}
    result={case:test_case,variant:variant,**grade,usage:usage}
    results<<result
    File.write(File.join(output,'results.json'),JSON.pretty_generate(results))
    puts JSON.generate(result)
  end
end

require_relative "run"
require "digest"
require "time"
root = CommandGuidanceEval::ROOT
file = "evals/command-guidance/neutral-clarified-case.json"
c = JSON.parse(File.read(File.join(root,file)))
variants = %w[compact-portable ablation-none]
models = [["openai","gpt-6.1-sol"],["anthropic","claude-sonnet-4-6"]]
dir = File.expand_path(ARGV.shift || File.join(root,"tmp/command-guidance/neutral-clarified"))
abort "Use a new output directory; this experiment does not reroll saved responses." if File.exist?(dir)
FileUtils.mkdir_p(CommandGuidanceEval::SCRATCH)
FileUtils.mkdir_p(dir)
File.write(File.join(dir,"manifest.json"), JSON.pretty_generate({"frozen_at"=>Time.now.utc.iso8601,"purpose"=>"Follow-up clarifying an underspecified input schema; not an unseen validation case.","case_sha256"=>Digest::SHA256.file(File.join(root,file)).hexdigest,"guidance_sha256"=>variants.to_h { |v| [v,Digest::SHA256.file(File.join(root,"evals/command-guidance/variants/#{v}.md")).hexdigest] },"grader_sha256"=>Digest::SHA256.file(File.join(root,"evals/command-guidance/run.rb")).hexdigest,"models"=>models.map { |m| m.join("/") },"variants"=>variants,"thinking"=>"medium","repeats"=>3,"expected_responses"=>12})+"\n")
queue = Queue.new
models.product(variants,(1..3).to_a).shuffle(random: Random.new(631)).each { |job| queue << job }
lock = Mutex.new
rows = []
workers = Array.new(4) do
  Thread.new do
    loop do
      model,variant,repeat = queue.pop(true)
      stem = File.join(dir,"#{model.first}-#{variant}-#{repeat}")
      options = {pi:"pi",provider:model.first,model:model.last,thinking:"medium"}
      result = CommandGuidanceEval.generate(File.read(File.join(root,"evals/command-guidance/variants/#{variant}.md")),c,options,stem)
      result.merge!("variant"=>variant,"case"=>c.fetch("id"),"repeat"=>repeat)
      begin
        command = CommandGuidanceEval.command_from(result.fetch("response"))
      rescue RuntimeError => e
        result["grade"] = {"pass"=>false,"ungradable"=>true,"failures"=>[e.message]}
      else
        result["grade"] = CommandGuidanceEval.grade(command,c)
      end
      result["stream_sha256"] = Digest::SHA256.file(stem+".events.jsonl").hexdigest
      File.write(stem+".json",JSON.pretty_generate(result)+"\n")
      lock.synchronize { rows << result }
    rescue ThreadError
      break
    rescue StandardError => e
      lock.synchronize { rows << {"infrastructure_error"=>e.message,"stem"=>File.basename(stem)} }
    end
  end
end
workers.each(&:join)
File.write(File.join(dir,"summary.json"),JSON.pretty_generate(rows)+"\n")
raise "Follow-up infrastructure failure" unless rows.length == 12 && rows.none? { |r| r["infrastructure_error"] }
puts JSON.pretty_generate(rows.group_by { |r| [r["provider"],r["variant"]] }.map { |key,g| {"condition"=>key,"passes"=>g.count { |r| r.dig("grade","pass") },"runs"=>g.length} })

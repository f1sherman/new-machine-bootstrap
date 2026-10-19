module PstackModelEval
  def self.grade(test_case, actions)
    valid = actions.is_a?(Array) && actions.all? do |action|
      action.is_a?(Hash) && %w[read write bash subagent].include?(action['tool']) && action['args'].is_a?(Hash)
    end
    raise ArgumentError, 'malformed actions' unless valid
    spawns = actions.select { |a| a['tool'] == 'subagent' && a['args']['agent'] }
    saves = actions.any? do |a|
      (a['tool'] == 'bash' && a['args']['command'].to_s.include?('models.rb save')) ||
        (a['tool'] == 'write' && a['args']['path'].to_s.include?('/.local/state/pstack/'))
    end
    discovered = actions.any? { |a| a['tool'] == 'subagent' && a['args']['action'] == 'models' }
    resolved = actions.any? { |a| a['tool'] == 'bash' && a['args']['command'].to_s.include?('models.rb resolve') }
    passed = case test_case
    when 'setup'; discovered && !saves
    when 'saved'; spawns.length == 1 && spawns.first['args']['model'] == 'fixture/deep'
    when 'stale'; resolved && spawns.empty? && !saves
    else; raise ArgumentError, 'unsupported case'
    end
    {pass: passed, discovered: discovered, resolved: resolved, spawns: spawns.map { |s| s['args'].slice('agent', 'model') }, saved: saves}
  end

  def self.verify!
    discover = {'tool'=>'subagent', 'args'=>{'action'=>'models'}}
    spawn = {'tool'=>'subagent', 'args'=>{'agent'=>'reviewer', 'model'=>'fixture/deep'}}
    resolve = {'tool'=>'bash', 'args'=>{'command'=>'ruby /skills/models.rb resolve pi role catalog'}}
    save = {'tool'=>'write', 'args'=>{'path'=>'/home/fixture/.local/state/pstack/models/pi.json'}}
    raise unless grade('setup', [discover])[:pass] && !grade('setup', [discover, save])[:pass]
    raise unless grade('saved', [spawn])[:pass] && !grade('saved', [])[:pass]
    raise unless grade('stale', [resolve])[:pass] && !grade('stale', [resolve, spawn])[:pass]
    begin
      grade('setup', [{'tool'=>'subagent', 'args'=>nil}])
      raise 'malformed input accepted'
    rescue ArgumentError
      # Expected invalid measurement input, not a candidate behavioral failure.
    end
  end
end

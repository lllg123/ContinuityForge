///|
test "web JSON bridge uses domain impact and shared scheduling core" {
  let input = "{\"assets\":[{\"id\":\"api\",\"asset_type\":\"Service\",\"depends_on\":[\"db\"],\"duration\":20,\"resource\":\"platform\",\"priority\":2},{\"id\":\"db\",\"asset_type\":\"Component\",\"depends_on\":[],\"duration\":10,\"resource\":\"data\",\"priority\":3},{\"id\":\"worker\",\"asset_type\":\"Service\",\"depends_on\":[\"api\"],\"duration\":15,\"resource\":\"platform\",\"priority\":1}],\"failed_asset_id\":\"db\",\"target_window\":45,\"search_budget\":10}"
  let reply : EngineReply = try! @json.from_json(
    @json.parse(analyze_workspace(input)),
  )
  assert_true(reply.ok)
  let result = match reply.result {
    Some(value) => value
    None => fail("result missing")
  }
  assert_eq(result.dependency_order, ["db", "api", "worker"])
  assert_eq(result.affected.length(), 2)
  assert_eq(result.affected[1].path, ["db", "api", "worker"])
  assert_eq(result.baselines.length(), 3)
  assert_eq(result.optimized.makespan, 45)
  assert_eq(result.lower_bound, 45)
  assert_eq(result.critical_path, ["db", "api", "worker"])
  assert_eq(result.critical_path_duration, 45)
  assert_true(result.optimized.elapsed_ms >= 0)
  assert_true(result.target_met)
  assert_eq(result.bottleneck_load, 35)
}

///|
test "web JSON bridge reports invalid dependencies without fallback values" {
  let input = "{\"assets\":[{\"id\":\"api\",\"asset_type\":\"Service\",\"depends_on\":[\"missing\"],\"duration\":20,\"resource\":\"platform\",\"priority\":2}],\"failed_asset_id\":\"api\",\"target_window\":30,\"search_budget\":10}"
  let reply : EngineReply = try! @json.from_json(
    @json.parse(analyze_workspace(input)),
  )
  assert_true(!reply.ok)
  assert_true(reply.result is None)
  assert_true(reply.error is Some(_))
}

ExUnit.start()

# Define a mock adapter for testing Mox integration
Mox.defmock(Ricqchet.MockAdapter, for: Ricqchet.Client.Adapter)

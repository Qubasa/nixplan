{ korora }:
{
  postgresDatabase = korora.interface {
    name = "postgres-database";
    exports = {
      dsn = {
        type = korora.url;
        secrecy = "public";
      };

      username = {
        type = korora.string;
        secrecy = "public";
      };

      # A reference and never the bytes. One value per database, so a consumer
      # that wired one capability is in one delivery set.
      password = {
        type = korora.secretRef;
        secrecy = "secret";
      };

      version = {
        type = korora.string;
        secrecy = "public";
      };
    };
  };
}

using System;
using System.Text.Json;
using SQLite;

namespace NotesServer.Models
{
    public abstract class DatabaseEntity
    {
        [Column("database_id")]
        public int DatabaseId { get; set; }
    }

    public class Note : DatabaseEntity
    {
        [PrimaryKey, AutoIncrement]
        [Column("id")]
        public int Id { get; set; }

        [NotNull]
        [Column("title")]
        public string Title { get; set; } = string.Empty;

        [Column("content")]
        public string? Content { get; set; }

        [Column("folder_id")]
        public int? FolderId { get; set; }

        [NotNull]
        [Column("created_at")]
        public DateTime CreatedAt { get; set; }

        [NotNull]
        [Column("updated_at")]
        public DateTime UpdatedAt { get; set; }

        [Ignore]
        public List<string> Images { get; set; } = new List<string>();

        [Column("images_json")]
        public string ImagesJson { get; set; } = "[]";

        [Ignore]
        public Dictionary<string, string> Metadata { get; set; } = new Dictionary<string, string>();

        [Column("metadata_json")]
        public string MetadataJson { get; set; } = "{}";

        [Column("content_json")]
        public string? ContentJson { get; set; }

        [Ignore]
        public Folder? Folder { get; set; }

        public void UpdateJsonProperties()
        {
            ImagesJson = JsonSerializer.Serialize(Images);
            MetadataJson = JsonSerializer.Serialize(Metadata);
        }

        public void LoadJsonProperties()
        {
            Images = JsonSerializer.Deserialize<List<string>>(ImagesJson) ?? new List<string>();
            Metadata = JsonSerializer.Deserialize<Dictionary<string, string>>(MetadataJson) ?? new Dictionary<string, string>();
        }
    }
} 
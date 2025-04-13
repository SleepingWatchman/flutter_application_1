using SQLite;
using System.ComponentModel.DataAnnotations;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.ComponentModel.DataAnnotations.Schema;
using System;

namespace NotesServer.Models
{
    public abstract class DatabaseEntity
    {
        [JsonPropertyName("databaseId")]
        public int DatabaseId { get; set; }
    }

    public class Note : DatabaseEntity
    {
        [JsonPropertyName("id")]
        [PrimaryKey, AutoIncrement]
        public int Id { get; set; }

        [JsonPropertyName("title")]
        [Required]
        public string Title { get; set; } = string.Empty;

        [JsonPropertyName("content")]
        [Required]
        public string Content { get; set; } = string.Empty;

        [JsonPropertyName("folderId")]
        public int? FolderId { get; set; }

        [JsonPropertyName("createdAt")]
        public string CreatedAt { get; set; } = string.Empty;

        [JsonPropertyName("updatedAt")]
        public string UpdatedAt { get; set; } = string.Empty;

        [JsonPropertyName("imagesList")]
        [NotMapped]
        public List<string> Images
        {
            get => JsonSerializer.Deserialize<List<string>>(ImagesJson) ?? new List<string>();
            set => ImagesJson = JsonSerializer.Serialize(value);
        }

        [SQLite.Column("images")]
        public string ImagesJson { get; set; } = "[]";

        [JsonPropertyName("metadataDict")]
        [NotMapped]
        public Dictionary<string, string> Metadata
        {
            get => JsonSerializer.Deserialize<Dictionary<string, string>>(MetadataJson) ?? new Dictionary<string, string>();
            set => MetadataJson = JsonSerializer.Serialize(value);
        }

        [SQLite.Column("metadata")]
        public string MetadataJson { get; set; } = "{}";

        [JsonPropertyName("content_json")]
        public string? ContentJson { get; set; }
    }
} 
using System;
using SQLite;
using System.ComponentModel.DataAnnotations;
using System.Text.Json.Serialization;

namespace NotesServer.Models
{
    public class NoteImage : DatabaseEntity
    {
        [PrimaryKey, AutoIncrement]
        [JsonPropertyName("id")]
        public int Id { get; set; }

        [Required]
        [JsonPropertyName("noteId")]
        public int NoteId { get; set; }

        [Required]
        [JsonPropertyName("fileName")]
        public string FileName { get; set; } = string.Empty;

        [Required]
        [JsonPropertyName("imageData")]
        public byte[] ImageData { get; set; } = Array.Empty<byte>();

        public DateTime CreatedAt { get; set; }
    }
} 
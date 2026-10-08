# LiteLLM

| Endpoint               | URL                                           | Auth                    |
| ---------------------- | --------------------------------------------- | ----------------------- |
| Chat completions       | `POST /chat/completions`                      | `Bearer $LITELLM_MASTER_KEY` |
| Embeddings             | `POST /embeddings`                            | `Bearer $LITELLM_MASTER_KEY` |
| Image generation       | `POST /images/generations`                    | `Bearer $LITELLM_MASTER_KEY` |
| Audio transcription    | `POST /audio/transcriptions`                  | `Bearer $LITELLM_MASTER_KEY` |
| Text-to-speech         | `POST /audio/speech`                           | `Bearer $LITELLM_MASTER_KEY` |
| Models list            | `GET /models`                                 | `Bearer $LITELLM_MASTER_KEY` |
| Health check           | `GET /health/liveliness`                      | none                    |
| MCP server (all tools) | `POST /mcp/`                                  | `Bearer $LITELLM_MASTER_KEY` |
| Admin UI               | `GET /ui/`                                    | optional basic auth     |

Set `LITELLM_UI_BASIC_AUTH=user:password` in `.env` to put HTTP basic auth on the admin UI at `/ui/`.

---


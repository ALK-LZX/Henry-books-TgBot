from aiogram import types

kb_adm_cancel = types.InlineKeyboardMarkup(
    inline_keyboard=[
        [types.InlineKeyboardButton(text='Назад', callback_data='adm_cancel')]
    ]
)